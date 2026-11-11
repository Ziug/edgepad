#import "MultitouchBridge.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOReturn.h>
#include <dlfcn.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

typedef struct { float x; float y; } MTPoint;
typedef struct { MTPoint position; MTPoint velocity; } MTVector;
typedef struct {
    int32_t frame;
    double timestamp;
    int32_t pathIndex;
    int32_t state;
    int32_t fingerID;
    int32_t handID;
    MTVector normalizedVector;
    float total;
    int32_t reserved9;
    float angle;
    float majorAxis;
    float minorAxis;
    MTVector absoluteVector;
    int32_t reserved14;
    int32_t reserved15;
    float density;
} MTTouch;

typedef CFTypeRef MTDeviceRef;
typedef void (*MTFrameCallback)(MTDeviceRef device, MTTouch *touches, size_t count, double timestamp, size_t frame);
typedef MTDeviceRef (*MTDeviceCreateDefaultFunction)(void);
typedef void (*MTRegisterContactFrameCallbackFunction)(MTDeviceRef device, MTFrameCallback callback);
typedef void (*MTUnregisterContactFrameCallbackFunction)(MTDeviceRef device, MTFrameCallback callback);
typedef IOReturn (*MTDeviceStartFunction)(MTDeviceRef device, int mode);
typedef IOReturn (*MTDeviceStopFunction)(MTDeviceRef device);
typedef CFMutableArrayRef (*MTDeviceCreateListFunction)(void);
typedef CFTypeRef (*MTActuatorCreateFromDeviceIDFunction)(uint64_t deviceID);
typedef IOReturn (*MTActuatorOpenFunction)(CFTypeRef actuator, uint32_t options);
typedef IOReturn (*MTActuatorCloseFunction)(CFTypeRef actuator);
typedef IOReturn (*MTActuatorActuateFunction)(CFTypeRef actuator, int32_t waveform, uint32_t option, float value1, float value2);

// States treated as "not a real contact": NotTracking, HoverInRange, OutOfRange.
#define EDGEPAD_STATE_NOT_TRACKING 0
#define EDGEPAD_STATE_HOVER 2
#define EDGEPAD_STATE_OUT_OF_RANGE 7

static pthread_mutex_t gLock = PTHREAD_MUTEX_INITIALIZER;
static void *gFramework = NULL;
static MTDeviceRef gDevice = NULL;
static MTRegisterContactFrameCallbackFunction gRegister = NULL;
static MTUnregisterContactFrameCallbackFunction gUnregister = NULL;
static MTDeviceStartFunction gStart = NULL;
static MTDeviceStopFunction gStop = NULL;
static EdgePadTouchFrameCallback gClientCallback = NULL;
static void *gClientContext = NULL;

// Haptic actuator symbols, resolved once on first use instead of per call.
static MTDeviceCreateListFunction gCreateList = NULL;
static MTActuatorCreateFromDeviceIDFunction gCreateActuator = NULL;
static MTActuatorOpenFunction gActuatorOpen = NULL;
static MTActuatorCloseFunction gActuatorClose = NULL;
static MTActuatorActuateFunction gActuatorActuate = NULL;
static bool gActuatorSymbolsResolved = false;
static CFTypeRef gHapticActuator = NULL;

static _Atomic(uint64_t) gHardwareFrames = 0;
static _Atomic(uint64_t) gDroppedIdleFrames = 0;
static _Atomic(int32_t) gHadActiveContacts = 0;
static _Atomic(int32_t) gPointerSuppressed = 0;

static bool EdgePadActuatorSymbolsResolved(void) {
    if (gActuatorSymbolsResolved) return true;
    if (gFramework == NULL) {
        gFramework = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_LAZY | RTLD_LOCAL);
    }
    if (gFramework == NULL) return false;
    gCreateList = (MTDeviceCreateListFunction)dlsym(gFramework, "MTDeviceCreateList");
    gCreateActuator = (MTActuatorCreateFromDeviceIDFunction)dlsym(gFramework, "MTActuatorCreateFromDeviceID");
    gActuatorOpen = (MTActuatorOpenFunction)dlsym(gFramework, "MTActuatorOpen");
    gActuatorClose = (MTActuatorCloseFunction)dlsym(gFramework, "MTActuatorClose");
    gActuatorActuate = (MTActuatorActuateFunction)dlsym(gFramework, "MTActuatorActuate");
    gActuatorSymbolsResolved = gCreateList != NULL && gCreateActuator != NULL &&
        gActuatorOpen != NULL && gActuatorClose != NULL && gActuatorActuate != NULL;
    return gActuatorSymbolsResolved;
}

static void EdgePadMultitouchFrame(MTDeviceRef device, MTTouch *touches, size_t count, double timestamp, size_t frame) {
    (void)device;
    (void)timestamp;
    (void)frame;
    atomic_fetch_add_explicit(&gHardwareFrames, 1, memory_order_relaxed);

    // Scan first: no lock, no allocation. The fast common case (nothing
    // touching the glass) returns after one atomic exchange.
    EdgePadContact buffer[64];
    size_t active = 0;
    if (touches != NULL) {
        for (size_t index = 0; index < count && index < 64; index++) {
            int32_t state = touches[index].state;
            if (state == EDGEPAD_STATE_NOT_TRACKING || state == EDGEPAD_STATE_HOVER ||
                state == EDGEPAD_STATE_OUT_OF_RANGE) {
                continue;
            }
            buffer[active].identifier = touches[index].fingerID;
            buffer[active].x = touches[index].normalizedVector.position.x;
            buffer[active].y = touches[index].normalizedVector.position.y;
            buffer[active].state = state;
            active++;
        }
    }

    if (active == 0) {
        if (!atomic_load_explicit(&gHadActiveContacts, memory_order_acquire)) {
            // Steady-state idle: no lock, no allocation, nothing scheduled in Swift.
            atomic_fetch_add_explicit(&gDroppedIdleFrames, 1, memory_order_relaxed);
            return;
        }
        pthread_mutex_lock(&gLock);
        EdgePadTouchFrameCallback callback = gClientCallback;
        void *context = gClientContext;
        pthread_mutex_unlock(&gLock);
        if (atomic_exchange_explicit(&gHadActiveContacts, 0, memory_order_acq_rel)) {
            // Activity just ended: deliver one final frame so Swift can end all tracks.
            if (callback != NULL) callback(NULL, 0, context);
        } else {
            atomic_fetch_add_explicit(&gDroppedIdleFrames, 1, memory_order_relaxed);
        }
        return;
    }
    atomic_store_explicit(&gHadActiveContacts, 1, memory_order_release);
    pthread_mutex_lock(&gLock);
    EdgePadTouchFrameCallback callback = gClientCallback;
    void *context = gClientContext;
    pthread_mutex_unlock(&gLock);
    if (callback != NULL) callback(buffer, active, context);
}

bool EdgePadStartListening(EdgePadTouchFrameCallback callback, void *context) {
    if (callback == NULL) return false;

    pthread_mutex_lock(&gLock);
    if (gDevice != NULL) {
        pthread_mutex_unlock(&gLock);
        return true;
    }
    pthread_mutex_unlock(&gLock);

    if (gFramework == NULL) {
        gFramework = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_LAZY | RTLD_LOCAL);
    }
    if (gFramework == NULL) return false;

    MTDeviceCreateDefaultFunction createDefault = (MTDeviceCreateDefaultFunction)dlsym(gFramework, "MTDeviceCreateDefault");
    gRegister = (MTRegisterContactFrameCallbackFunction)dlsym(gFramework, "MTRegisterContactFrameCallback");
    gUnregister = (MTUnregisterContactFrameCallbackFunction)dlsym(gFramework, "MTUnregisterContactFrameCallback");
    gStart = (MTDeviceStartFunction)dlsym(gFramework, "MTDeviceStart");
    gStop = (MTDeviceStopFunction)dlsym(gFramework, "MTDeviceStop");
    if (createDefault == NULL || gRegister == NULL || gStart == NULL) return false;

    MTDeviceRef device = createDefault();
    if (device == NULL) return false;

    pthread_mutex_lock(&gLock);
    gClientCallback = callback;
    gClientContext = context;
    gDevice = device;
    pthread_mutex_unlock(&gLock);

    gRegister(device, EdgePadMultitouchFrame);
    if (gStart(device, 0) != kIOReturnSuccess) {
        EdgePadStopListening();
        return false;
    }
    return true;
}

void EdgePadStopListening(void) {
    pthread_mutex_lock(&gLock);
    MTDeviceRef device = gDevice;
    gDevice = NULL;
    gClientCallback = NULL;
    gClientContext = NULL;
    pthread_mutex_unlock(&gLock);
    atomic_store_explicit(&gHadActiveContacts, 0, memory_order_release);
    EdgePadSetPointerSuppressed(false);

    if (device == NULL) return;
    if (gUnregister != NULL) gUnregister(device, EdgePadMultitouchFrame);
    if (gStop != NULL) gStop(device);
    CFRelease(device);
}

bool EdgePadPlayHaptic(int32_t waveform) {
    if (!EdgePadActuatorSymbolsResolved()) return false;

    if (gHapticActuator == NULL) {
        CFMutableArrayRef devices = gCreateList();
        if (devices == NULL) return false;
        for (CFIndex i = 0; i < CFArrayGetCount(devices) && gHapticActuator == NULL; i++) {
            const void *device = CFArrayGetValueAtIndex(devices, i);
            uint64_t deviceID = 0;
            memcpy(&deviceID, (const uint8_t *)device + 64, sizeof(deviceID));
            CFTypeRef actuator = gCreateActuator(deviceID);
            if (actuator == NULL) continue;
            if (gActuatorOpen(actuator, 0) == kIOReturnSuccess) {
                gActuatorClose(actuator);
                gHapticActuator = actuator;
            } else {
                CFRelease(actuator);
            }
        }
        CFRelease(devices);
    }

    if (gHapticActuator == NULL || gActuatorOpen(gHapticActuator, 0) != kIOReturnSuccess) return false;
    bool success = gActuatorActuate(gHapticActuator, waveform, 0, 0.0f, 0.0f) == kIOReturnSuccess;
    gActuatorClose(gHapticActuator);
    return success;
}

void EdgePadSetPointerSuppressed(bool suppressed) {
    atomic_store_explicit(&gPointerSuppressed, suppressed ? 1 : 0, memory_order_release);
}

bool EdgePadIsPointerSuppressed(void) {
    return atomic_load_explicit(&gPointerSuppressed, memory_order_acquire) != 0;
}

uint64_t EdgePadHardwareFrameCount(void) {
    return atomic_load_explicit(&gHardwareFrames, memory_order_relaxed);
}

uint64_t EdgePadDroppedIdleFrameCount(void) {
    return atomic_load_explicit(&gDroppedIdleFrames, memory_order_relaxed);
}

void EdgePadResetFrameCounters(void) {
    atomic_store_explicit(&gHardwareFrames, 0, memory_order_relaxed);
    atomic_store_explicit(&gDroppedIdleFrames, 0, memory_order_relaxed);
}
