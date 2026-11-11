#ifndef EdgePad_MultitouchBridge_h
#define EdgePad_MultitouchBridge_h

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct {
    int32_t identifier;
    float x;
    float y;
    int32_t state;
} EdgePadContact;

// Called only when a frame contains at least one active contact, or when
// activity ends (a single final frame with count == 0 / NULL contacts).
// Steady-state idle frames are dropped natively and never reach Swift.
typedef void (*EdgePadTouchFrameCallback)(const EdgePadContact *contacts, size_t count, void *context);

bool EdgePadStartListening(EdgePadTouchFrameCallback callback, void *context);
void EdgePadStopListening(void);
bool EdgePadPlayHaptic(int32_t waveform);

// Atomic suppression flag read by the event-tap hot path (no locks).
void EdgePadSetPointerSuppressed(bool suppressed);
bool EdgePadIsPointerSuppressed(void);

// Cumulative native-side counters for diagnostics.
uint64_t EdgePadHardwareFrameCount(void);
uint64_t EdgePadDroppedIdleFrameCount(void);
void EdgePadResetFrameCounters(void);

#endif
