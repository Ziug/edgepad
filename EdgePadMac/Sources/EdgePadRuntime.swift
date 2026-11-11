import AppKit
import ApplicationServices
import Combine
import CoreAudio
import CoreHaptics
import CoreGraphics
import Darwin
import IOKit.graphics
import IOKit.hid
import os

enum EdgeControl: Equatable {
    case brightness
    case volume
}

struct DiagnosticsSnapshot {
    var framesPerSecond: Double
    var processedPerSecond: Double
    var idleDroppedPerSecond: Double
    var writesPerSecond: Double
    var hapticsPerSecond: Double
    var warpsPerSecond: Double
    var mediaKeysPerSecond: Double
    var totalMediaKeys: Int64
    var totalHardwareFrames: UInt64
    var totalProcessedFrames: Int64
}

@MainActor
final class EdgePadRuntime: ObservableObject {
    @Published private(set) var brightness = 50.0
    @Published private(set) var volume = 50.0
    @Published private(set) var isMuted = false
    @Published private(set) var isListening = false
    @Published private(set) var isSuppressingPointer = false
    @Published private(set) var isPointerMonitoringAvailable = false
    @Published private(set) var isAccessibilityTrusted = false
    @Published private(set) var isTouchInputAuthorized = false
    @Published private(set) var activeEdge: EdgeControl?
    @Published private(set) var touchCount = 0
    @Published private(set) var lastTouchPoint: CGPoint?
    @Published private(set) var inputStatus = "Starting touchpad listener…"
    @Published private(set) var controlError: String?

    private let cursorFilter = edgePadCursorEventFilter
    private let haptics = EdgePadHaptics()
    private var contacts: [Int32: ContactTrack] = [:]
    private var lastMuteTap: TimeInterval?
    private var previousVolume = 50.0
    private var diagnosticsVisible = false
    private var lastDiagnosticsPush: TimeInterval = 0

    init() {
        UserDefaults.standard.register(defaults: [
            "edgepad.enabled": true,
            "edgepad.quickMute": true,
            "edgepad.haptics": true,
            "edgepad.freezeCursor": true,
            "edgepad.fineControl": true,
            "edgepad.swapSides": false,
            "edgepad.mediaStrip": true,
            "edgepad.mediaTapPlayPause": false,
            "edgepad.hapticsStrength": "strong",
            "edgepad.bottomQuarterOnly": false,
            "edgepad.requireModifier": false,
            "edgepad.edgeWidth": 5.0,
            "edgepad.sensitivity": 1.0
        ])
        refreshSystemValues()
    }

    func start() {
        guard UserDefaults.standard.bool(forKey: "edgepad.enabled") else {
            inputStatus = "Edge controls are paused"
            return
        }

        isTouchInputAuthorized = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        let started = EdgePadStartListening(edgePadTouchFrameCallback, Unmanaged.passUnretained(self).toOpaque())
        guard started else {
            inputStatus = "Could not start the trackpad listener"
            return
        }
        isListening = true

        isAccessibilityTrusted = AXIsProcessTrusted()
        if UserDefaults.standard.bool(forKey: "edgepad.freezeCursor"), cursorFilter.start() {
            isPointerMonitoringAvailable = true
            inputStatus = isTouchInputAuthorized
                ? "Trackpad connected · pointer freeze is ready"
                : "Allow Input Monitoring to receive trackpad touches"
        } else {
            isPointerMonitoringAvailable = false
            inputStatus = isTouchInputAuthorized
                ? "Trackpad connected · allow Accessibility to freeze the pointer"
                : "Allow Input Monitoring to receive trackpad touches"
        }
    }

    func requestTouchInputAccess() {
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        isTouchInputAuthorized = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        if !isTouchInputAuthorized {
            openInputMonitoringSettings()
        } else {
            start()
        }
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "edgepad.enabled")
        enabled ? start() : stop()
    }

    func setFreezeCursor(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "edgepad.freezeCursor")
        if enabled {
            isPointerMonitoringAvailable = cursorFilter.start()
            inputStatus = isPointerMonitoringAvailable
                ? "Trackpad connected · pointer freeze is ready"
                : "Trackpad connected · allow Accessibility to freeze the pointer"
        } else {
            cursorFilter.setSuppressed(false)
            cursorFilter.stop()
            isPointerMonitoringAvailable = false
            isSuppressingPointer = false
            inputStatus = "Trackpad connected · pointer freeze is off"
        }
    }

    func requestPointerAccess() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        isAccessibilityTrusted = AXIsProcessTrusted()
        isPointerMonitoringAvailable = cursorFilter.start()
        if isPointerMonitoringAvailable {
            inputStatus = "Trackpad connected · pointer freeze is ready"
        } else {
            openAccessibilitySettings()
        }
    }

    func stop() {
        EdgePadStopListening()
        contacts.removeAll()
        cursorFilter.setSuppressed(false)
        cursorFilter.stop()
        activeEdge = nil
        isSuppressingPointer = false
        isPointerMonitoringAvailable = false
        isListening = false
        inputStatus = "Edge controls are paused"
    }

    func refreshSystemValues() {
        if let value = SystemDisplay.readBrightness() {
            brightness = Double(value * 100)
        }
        if let value = SystemAudio.readVolume() {
            volume = Double(value * 100)
            if value > 0 { previousVolume = volume }
            isMuted = SystemAudio.readMuted() ?? (value == 0)
        }
    }

    func setBrightness(_ percent: Double) {
        let value = min(100, max(0, percent))
        guard SystemDisplay.setBrightness(Float(value / 100)) else {
            controlError = "macOS could not set brightness for the current display."
            return
        }
        brightness = value
        controlError = nil
        LevelHUD.shared.show(.brightness, value: value)
    }

    func setVolume(_ percent: Double) {
        let value = min(100, max(0, percent))
        guard SystemAudio.setVolume(Float(value / 100)) else {
            controlError = "The current audio output does not expose a writable system volume control."
            return
        }
        volume = value
        isMuted = value == 0
        if value > 0 { previousVolume = value }
        controlError = nil
        LevelHUD.shared.show(.volume, value: value, muted: isMuted)
    }

    func toggleMute() {
        if isMuted {
            if SystemAudio.setMuted(false) {
                isMuted = false
                controlError = nil
                LevelHUD.shared.show(.volume, value: volume, muted: false)
            } else {
                // Device without a settable mute: fall back to restoring the scalar.
                setVolume(previousVolume > 0 ? previousVolume : 50)
            }
        } else {
            previousVolume = max(volume, 1)
            if SystemAudio.setMuted(true) {
                // Device-level mute: volume scalar is untouched, so sound
                // returns at the exact previous level on unmute.
                isMuted = true
                controlError = nil
                LevelHUD.shared.show(.volume, value: 0, muted: true)
            } else {
                // No settable mute on this device — best we can do is scalar 0.
                setVolume(0)
            }
        }
        playMuteHaptic()
    }

    func setDiagnosticsVisible(_ visible: Bool) {
        diagnosticsVisible = visible
        if visible { lastDiagnosticsPush = 0 }
    }

    func diagnosticsSnapshot() -> DiagnosticsSnapshot {
        edgePadMetrics.snapshot()
    }

    func resetDiagnostics() {
        edgePadMetrics.reset()
    }

    func previewMuteHaptic() {
        playMuteHaptic()
    }

    /// Applies a batched level change for the whole frame at once: a single
    /// system write, a single publish and at most one step haptic — no matter
    /// how many step thresholds the frame crossed.
    private func applyLevelDelta(_ edge: EdgeControl, delta: Double, fine: Bool) {
        switch edge {
        case .brightness:
            let value = min(100, max(0, brightness + delta))
            guard value != brightness else { return }
            guard SystemDisplay.setBrightness(Float(value / 100)) else {
                controlError = "macOS could not set brightness for the current display."
                return
            }
            brightness = value
            controlError = nil
            LevelHUD.shared.show(.brightness, value: value)
        case .volume:
            let value = min(100, max(0, volume + delta))
            guard value != volume else { return }
            guard SystemAudio.setVolume(Float(value / 100)) else {
                controlError = "The current audio output does not expose a writable system volume control."
                return
            }
            volume = value
            isMuted = value == 0
            if value > 0 { previousVolume = value }
            controlError = nil
            LevelHUD.shared.show(.volume, value: value, muted: isMuted)
        }
        edgePadMetrics.systemWrite()
        if UserDefaults.standard.bool(forKey: "edgepad.haptics") {
            haptics.playStep(isFine: fine)
            edgePadMetrics.hapticPlayed()
        }
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    func openInputMonitoringSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else { return }
        NSWorkspace.shared.open(url)
    }

    // Frames arriving here have either at least one active contact (already
    // filtered natively) or are the single final idle transition frame.
    fileprivate func process(_ frame: [TrackpadContact]) {
        let now = ProcessInfo.processInfo.systemUptime

        edgePadCursorEventFilter.updateImmediately(for: frame)
        edgePadCursorEventFilter.holdCursorPosition()

        if diagnosticsVisible {
            let shouldPush = now - lastDiagnosticsPush >= 0.1
            if shouldPush {
                lastDiagnosticsPush = now
                if touchCount != frame.count { touchCount = frame.count }
                let point = frame.first.map { CGPoint(x: $0.x, y: $0.y) }
                if lastTouchPoint != point { lastTouchPoint = point }
            }
        }
        let activeIDs = Set(frame.map(\.identifier))

        for touch in frame {
            let point = CGPoint(x: touch.x, y: touch.y)
            if var track = contacts[touch.identifier] {
                let dx = point.x - track.last.x
                let dy = point.y - track.last.y
                track.last = point
                track.travel += hypot(dx, dy)

                // Media Strip: a mostly-horizontal swipe starting on the
                // bottom edge skips tracks. One fire per touch. The zone is a
                // fixed bottom strip (not the Edge Width) so it's easy to hit.
                if !track.mediaKeyFired, UserDefaults.standard.bool(forKey: "edgepad.mediaStrip") {
                    let dxTotal = point.x - track.start.x
                    let dyTotal = point.y - track.start.y
                    if track.start.y <= 0.12,
                       abs(dxTotal) >= 0.14,
                       abs(dxTotal) >= abs(dyTotal) * 1.6 {
                        track.mediaKeyFired = true
                        MediaRemote.post(dxTotal < 0 ? MediaRemote.nextTrack : MediaRemote.previousTrack)
                        edgePadMetrics.mediaKeySent()
                    }
                }

                if let edge = track.edge, isInside(point, edge: edge) {
                    track.verticalRemainder += dy
                    let fine = isFineControlActive
                    let sensitivity = max(0.25, min(2.0, UserDefaults.standard.double(forKey: "edgepad.sensitivity")))
                    let threshold = CGFloat((fine ? 1.0 / 64.0 : 1.0 / 16.0) / sensitivity)
                    let absRemainder = abs(track.verticalRemainder)
                    let wholeSteps = absRemainder >= threshold ? floor(absRemainder / threshold) : 0
                    if wholeSteps >= 1 {
                        let direction: CGFloat = track.verticalRemainder > 0 ? 1.0 : -1.0
                        let stepSize = CGFloat(100.0 / 16.0) * (fine ? CGFloat(0.25) : CGFloat(1))
                        applyLevelDelta(edge, delta: Double(direction * wholeSteps * stepSize), fine: fine)
                        track.verticalRemainder -= direction * wholeSteps * threshold
                    }
                } else if track.edge == nil, let edge = edgeFor(point) {
                    track.edge = edge
                }
                contacts[touch.identifier] = track
            } else {
                contacts[touch.identifier] = ContactTrack(
                    start: point,
                    last: point,
                    edge: edgeFor(point),
                    isMuteTap: UserDefaults.standard.bool(forKey: "edgepad.quickMute") && isMuteCorner(point),
                    startedAt: now
                )
            }
        }

        let endedIDs = contacts.keys.filter { !activeIDs.contains($0) }
        for id in endedIDs {
            guard let track = contacts.removeValue(forKey: id) else { continue }
            if UserDefaults.standard.bool(forKey: "edgepad.mediaTapPlayPause"),
               !track.mediaKeyFired,
               track.start.y <= 0.12,
               now - track.startedAt < 0.30,
               track.travel < 0.03 {
                MediaRemote.post(MediaRemote.playPause)
                edgePadMetrics.mediaKeySent()
            }
            guard track.isMuteTap, now - track.startedAt < 0.34, track.travel < 0.035 else { continue }
            if let previous = lastMuteTap, now - previous < 0.42 {
                lastMuteTap = nil
                toggleMute()
            } else {
                lastMuteTap = now
            }
        }

        let newActiveEdge = contacts.values.first(where: { $0.edge != nil })?.edge
        if activeEdge != newActiveEdge { activeEdge = newActiveEdge }
        let shouldSuppress = UserDefaults.standard.bool(forKey: "edgepad.freezeCursor") && contacts.values.contains { track in
            track.edge.map { isInside(track.last, edge: $0) } ?? track.isMuteTap
        }
        let suppressing = shouldSuppress && cursorFilter.isAvailable
        if isSuppressingPointer != suppressing { isSuppressingPointer = suppressing }
    }

    private func edgeFor(_ point: CGPoint) -> EdgeControl? {
        if UserDefaults.standard.bool(forKey: "edgepad.requireModifier"), !hasSlideModifier { return nil }
        if UserDefaults.standard.bool(forKey: "edgepad.bottomQuarterOnly"), point.y > 0.25 { return nil }
        let edgeWidth = max(0.02, min(0.2, UserDefaults.standard.double(forKey: "edgepad.edgeWidth") / 100))
        if point.x <= edgeWidth { return UserDefaults.standard.bool(forKey: "edgepad.swapSides") ? .volume : .brightness }
        if point.x >= 1 - edgeWidth && !isMuteCorner(point) { return UserDefaults.standard.bool(forKey: "edgepad.swapSides") ? .brightness : .volume }
        return nil
    }

    private func isInside(_ point: CGPoint, edge: EdgeControl) -> Bool {
        if UserDefaults.standard.bool(forKey: "edgepad.bottomQuarterOnly"), point.y > 0.25 { return false }
        let swapSides = UserDefaults.standard.bool(forKey: "edgepad.swapSides")
        let isLeftEdge = point.x <= edgeWidth
        let isRightEdge = point.x >= 1 - edgeWidth
        switch edge {
        case .brightness:
            return swapSides ? isRightEdge : isLeftEdge
        case .volume:
            return (swapSides ? isLeftEdge : isRightEdge) && !isMuteCorner(point)
        }
    }

    private var edgeWidth: CGFloat {
        CGFloat(max(0.02, min(0.2, UserDefaults.standard.double(forKey: "edgepad.edgeWidth") / 100)))
    }

    private var isFineControlActive: Bool {
        UserDefaults.standard.bool(forKey: "edgepad.fineControl") &&
        NSEvent.modifierFlags.contains([.shift, .option])
    }

    private var hasSlideModifier: Bool {
        NSEvent.modifierFlags.contains(.function) || NSEvent.modifierFlags.contains(.option)
    }

    private func isMuteCorner(_ point: CGPoint) -> Bool {
        UserDefaults.standard.bool(forKey: "edgepad.quickMute") && point.x >= 0.88 && point.y >= 0.88
    }

    private func playMuteHaptic() {
        guard UserDefaults.standard.bool(forKey: "edgepad.haptics") else { return }
        haptics.playMuteDoubleTap()
    }
}

@MainActor
private final class EdgePadHaptics {
    private let engine: CHHapticEngine?
    private let performer = NSHapticFeedbackManager.defaultPerformer
    private var engineStarted = false

    init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            engine = nil
            return
        }
        engine = try? CHHapticEngine()
    }

    func playStep(isFine: Bool) {
        let strength = UserDefaults.standard.string(forKey: "edgepad.hapticsStrength") ?? "strong"
        let scale: Float = strength == "light" ? 0.55 : strength == "medium" ? 0.78 : 1.0
        let intensity: Float = (isFine ? 0.18 : 0.48) * scale
        let sharpness: Float = (isFine ? 0.22 : 0.58) * (0.7 + 0.3 * scale)
        let event = transient(at: 0, intensity: intensity, sharpness: sharpness)
        guard !play([event]) else { return }
        performer.perform(isFine ? .alignment : .levelChange, performanceTime: .now)
    }

    func playMuteDoubleTap() {
        if !EdgePadPlayHaptic(3) { performer.perform(.generic, performanceTime: .now) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [performer] in
            if !EdgePadPlayHaptic(3) { performer.perform(.generic, performanceTime: .now) }
        }
    }

    private func transient(at time: TimeInterval, intensity: Float, sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: time
        )
    }

    private func play(_ events: [CHHapticEvent]) -> Bool {
        guard let engine else { return false }
        do {
            if !engineStarted {
                try engine.start()
                engineStarted = true
            }
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
            return true
        } catch {
            return false
        }
    }
}

fileprivate struct TrackpadContact: Sendable {
    let identifier: Int32
    let x: CGFloat
    let y: CGFloat
    let state: Int32
}

// Posts system media keys as system-defined events (NX_KEYTYPE_PLAY/NEXT/PREVIOUS),
// which target whatever app currently owns Now Playing.
private enum MediaRemote {
    static let playPause: UInt16 = 16
    static let nextTrack: UInt16 = 17
    static let previousTrack: UInt16 = 18

    static func post(_ key: UInt16) {
        func makeEvent(_ isDown: Bool) -> NSEvent? {
            let data1 = (Int(key) << 16) | ((isDown ? 0xA : 0xB) << 8)
            let flags = NSEvent.ModifierFlags(rawValue: isDown ? 0xA00 : 0xB00)
            return NSEvent.otherEvent(with: .systemDefined,
                                      location: .zero,
                                      modifierFlags: flags,
                                      timestamp: ProcessInfo.processInfo.systemUptime,
                                      windowNumber: 0,
                                      context: nil,
                                      subtype: 8,
                                      data1: data1,
                                      data2: -1)
        }
        makeEvent(true)?.cgEvent?.post(tap: .cghidEventTap)
        makeEvent(false)?.cgEvent?.post(tap: .cghidEventTap)
    }
}

private let edgePadTouchFrameCallback: EdgePadTouchFrameCallback = { rawContacts, count, context in
    guard let context else { return }
    let runtime = Unmanaged<EdgePadRuntime>.fromOpaque(context).takeUnretainedValue()
    if let rawContacts, count > 0 {
        var contacts: [TrackpadContact] = []
        contacts.reserveCapacity(Int(count))
        for index in 0..<Int(count) {
            let contact = rawContacts[index]
            contacts.append(TrackpadContact(
                identifier: contact.identifier,
                x: CGFloat(contact.x),
                y: CGFloat(contact.y),
                state: contact.state
            ))
        }
        edgePadFrameStore.submit(contacts, runtime: runtime)
    } else {
        // Single final idle frame after activity ended: deliver it so tracks
        // end and the cursor is released, without any further work.
        edgePadFrameStore.submit([], runtime: runtime)
    }
}

// Keeps only the newest frame and drains it on the main thread at a bounded
// rate (~60 Hz). Hardware frames that arrive between drains are superseded,
// which is exactly what we want for continuous edge control: the system
// always acts on the freshest position, never on stale backlog.
private final class FrameStore: @unchecked Sendable {
    private struct State {
        var pending: [TrackpadContact]?
        var pumpScheduled = false
        var lastDrain: TimeInterval = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let interval = 1.0 / 60.0

    func submit(_ contacts: [TrackpadContact], runtime: EdgePadRuntime) {
        let delay = state.withLock { state -> TimeInterval? in
            state.pending = contacts
            if state.pumpScheduled { return nil }
            state.pumpScheduled = true
            let now = ProcessInfo.processInfo.systemUptime
            return max(0, interval - (now - state.lastDrain))
        }
        guard let delay else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.drain(runtime: runtime)
        }
    }

    private func drain(runtime: EdgePadRuntime) {
        let frame = state.withLock { state -> [TrackpadContact]? in
            state.pumpScheduled = false
            state.lastDrain = ProcessInfo.processInfo.systemUptime
            let frame = state.pending
            state.pending = nil
            return frame
        }
        guard let frame else { return }
        edgePadMetrics.processedFrame()
        MainActor.assumeIsolated {
            runtime.process(frame)
        }
    }
}

private let edgePadFrameStore = FrameStore()

private final class EdgePadMetrics: @unchecked Sendable {
    private struct Counters {
        var processed: Int64 = 0
        var writes: Int64 = 0
        var haptics: Int64 = 0
        var warps: Int64 = 0
        var mediaKeys: Int64 = 0
    }

    private struct State {
        var counters = Counters()
        var lastSampleTime: TimeInterval = 0
        var lastSampleHardware: UInt64 = 0
        var lastSampleIdle: UInt64 = 0
        var lastSampleCounters = Counters()
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    init() {
        state.withLock { state in
            state.lastSampleTime = ProcessInfo.processInfo.systemUptime
            state.lastSampleHardware = EdgePadHardwareFrameCount()
            state.lastSampleIdle = EdgePadDroppedIdleFrameCount()
        }
    }

    func processedFrame() { state.withLock { $0.counters.processed &+= 1 } }
    func systemWrite() { state.withLock { $0.counters.writes &+= 1 } }
    func hapticPlayed() { state.withLock { $0.counters.haptics &+= 1 } }
    func cursorWarped() { state.withLock { $0.counters.warps &+= 1 } }
    func mediaKeySent() { state.withLock { $0.counters.mediaKeys &+= 1 } }

    func snapshot() -> DiagnosticsSnapshot {
        state.withLock { state in
            let now = ProcessInfo.processInfo.systemUptime
            let elapsed = max(now - state.lastSampleTime, 0.001)
            let hardware = EdgePadHardwareFrameCount()
            let idle = EdgePadDroppedIdleFrameCount()
            let snapshot = DiagnosticsSnapshot(
                framesPerSecond: Double(hardware - state.lastSampleHardware) / elapsed,
                processedPerSecond: Double(state.counters.processed - state.lastSampleCounters.processed) / elapsed,
                idleDroppedPerSecond: Double(idle - state.lastSampleIdle) / elapsed,
                writesPerSecond: Double(state.counters.writes - state.lastSampleCounters.writes) / elapsed,
                hapticsPerSecond: Double(state.counters.haptics - state.lastSampleCounters.haptics) / elapsed,
                warpsPerSecond: Double(state.counters.warps - state.lastSampleCounters.warps) / elapsed,
                mediaKeysPerSecond: Double(state.counters.mediaKeys - state.lastSampleCounters.mediaKeys) / elapsed,
                totalMediaKeys: state.counters.mediaKeys,
                totalHardwareFrames: hardware,
                totalProcessedFrames: state.counters.processed
            )
            state.lastSampleTime = now
            state.lastSampleHardware = hardware
            state.lastSampleIdle = idle
            state.lastSampleCounters = state.counters
            return snapshot
        }
    }

    func reset() {
        EdgePadResetFrameCounters()
        state.withLock { state in
            state.counters = Counters()
            state.lastSampleTime = ProcessInfo.processInfo.systemUptime
            state.lastSampleHardware = 0
            state.lastSampleIdle = 0
            state.lastSampleCounters = Counters()
        }
    }
}

private let edgePadMetrics = EdgePadMetrics()

private struct ContactTrack {
    let start: CGPoint
    var last: CGPoint
    var edge: EdgeControl?
    let isMuteTap: Bool
    let startedAt: TimeInterval
    var verticalRemainder: CGFloat = 0
    var travel: CGFloat = 0
    var mediaKeyFired = false
}

private final class CursorEventFilter {
    private struct AnchorState {
        var suppressed = false
        var anchor: CGPoint?
        var lastDriftCheck: TimeInterval = 0
        var lastWarp: TimeInterval = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: AnchorState())
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private(set) var isAvailable = false

    func updateImmediately(for contacts: [TrackpadContact]) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "edgepad.enabled"), defaults.bool(forKey: "edgepad.freezeCursor") else {
            setSuppressed(false)
            return
        }

        let edgeWidth = CGFloat(max(0.02, min(0.2, defaults.double(forKey: "edgepad.edgeWidth") / 100)))
        let bottomQuarterOnly = defaults.bool(forKey: "edgepad.bottomQuarterOnly")
        let requireModifier = defaults.bool(forKey: "edgepad.requireModifier")
        let quickMute = defaults.bool(forKey: "edgepad.quickMute")
        let flags = CGEventSource.flagsState(.combinedSessionState)
        let hasRequiredModifier = flags.contains(.maskAlternate) || flags.contains(.maskSecondaryFn)

        let shouldSuppress = contacts.contains { touch in
            guard touch.state != 0, touch.state != 2, touch.state != 7 else { return false }
            let point = CGPoint(x: touch.x, y: touch.y)
            let isMuteCorner = quickMute && point.x >= 0.88 && point.y >= 0.88
            if isMuteCorner { return true }
            if bottomQuarterOnly && point.y > 0.25 { return false }
            if requireModifier && !hasRequiredModifier { return false }
            let isLeftEdge = point.x <= edgeWidth
            let isRightEdge = point.x >= 1 - edgeWidth
            return isLeftEdge || isRightEdge
        }
        setSuppressed(shouldSuppress)
    }

    func start() -> Bool {
        if eventTap != nil { return isAvailable }

        // This tap only observes and suppresses mouse events. Post Event access
        // controls synthesizing events and is not required for an intercepting tap.
        guard AXIsProcessTrusted() else {
            isAvailable = false
            return false
        }

        let types: [CGEventType] = [
            .mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged, .otherMouseDragged
        ]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let filter = Unmanaged<CursorEventFilter>.fromOpaque(userInfo).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = filter.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                    return Unmanaged.passUnretained(event)
                }
                return EdgePadIsPointerSuppressed() ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: pointer
        ) else {
            isAvailable = false
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isAvailable = true
        return true
    }

    func stop() {
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let eventTap { CFMachPortInvalidate(eventTap) }
        runLoopSource = nil
        eventTap = nil
        isAvailable = false
        EdgePadSetPointerSuppressed(false)
        state.withLock { state in
            state.suppressed = false
            state.anchor = nil
        }
    }

    func setSuppressed(_ suppressed: Bool) {
        let changed = state.withLock { state -> Bool in
            let changed = state.suppressed != suppressed
            state.suppressed = suppressed
            if changed {
                state.anchor = suppressed ? (CGEvent(source: nil)?.location ?? NSEvent.mouseLocation) : nil
                state.lastDriftCheck = 0
                state.lastWarp = 0
            }
            return changed
        }
        EdgePadSetPointerSuppressed(suppressed)
        if changed {
            _ = CGAssociateMouseAndMouseCursorPosition(suppressed ? 0 : 1)
        }
    }

    // Event suppression and cursor association are the normal path. This is a
    // last-resort correction only: it runs at most 10x/s, skips the check
    // entirely when the cursor has not drifted from the anchor, and is
    // rate-limited even then.
    func holdCursorPosition() {
        let check = state.withLock { state -> (anchor: CGPoint, now: TimeInterval)? in
            guard state.suppressed, let anchor = state.anchor else { return nil }
            let now = ProcessInfo.processInfo.systemUptime
            guard now - state.lastDriftCheck >= 0.1 else { return nil }
            state.lastDriftCheck = now
            return (anchor, now)
        }
        guard let (anchor, now) = check else { return }
        guard let current = CGEvent(source: nil)?.location else { return }
        guard hypot(current.x - anchor.x, current.y - anchor.y) > 2 else { return }
        let shouldWarp = state.withLock { state -> Bool in
            guard now - state.lastWarp >= 0.1 else { return false }
            state.lastWarp = now
            return true
        }
        guard shouldWarp else { return }
        _ = CGWarpMouseCursorPosition(anchor)
        edgePadMetrics.cursorWarped()
    }
}

private let edgePadCursorEventFilter = CursorEventFilter()

private enum SystemAudio {
    static func readVolume() -> Float? {
        guard let device = defaultOutputDevice() else { return nil }
        var value: Float = 0
        var size = UInt32(MemoryLayout<Float>.size)
        var address = volumeAddress
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    static func setVolume(_ value: Float) -> Bool {
        guard let device = defaultOutputDevice() else { return false }
        var volume = min(1, max(0, value))
        let size = UInt32(MemoryLayout<Float>.size)
        var address = volumeAddress
        let result = AudioObjectSetPropertyData(device, &address, 0, nil, size, &volume) == noErr
        if result {
            // Ride the device's real mute along with scalar 0 so "silence" is
            // actual silence on outputs whose scalar floor isn't inaudible;
            // unmute on any non-zero set.
            _ = setMuted(value == 0, device: device)
        }
        return result
    }

    static func setMuted(_ muted: Bool, device: AudioObjectID? = nil) -> Bool {
        guard let device = device ?? defaultOutputDevice() else { return false }
        var address = muteAddress
        guard AudioObjectHasProperty(device, &address) else { return false }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else { return false }
        var value: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectSetPropertyData(device, &address, 0, nil, size, &value) == noErr
    }

    static func readMuted() -> Bool? {
        guard let device = defaultOutputDevice() else { return nil }
        var address = muteAddress
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value != 0
    }

    private static var volumeAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static var muteAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func defaultOutputDevice() -> AudioObjectID? {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        ) == noErr, device != kAudioObjectUnknown else { return nil }
        return device
    }
}

private enum SystemDisplay {
    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let framework = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
        RTLD_LAZY
    )

    static func readBrightness() -> Float? {
        let display = CGMainDisplayID()
        if let framework, let symbol = dlsym(framework, "DisplayServicesGetBrightness") {
            let get = unsafeBitCast(symbol, to: GetBrightness.self)
            var value: Float = 0
            if get(display, &value) == 0 { return min(1, max(0, value)) }
        }

        var value: Float = 0
        return withDisplayService { service in
            let key = "brightness" as CFString
            guard IODisplayGetFloatParameter(service, 0, key, &value) == kIOReturnSuccess else { return nil }
            return min(1, max(0, value))
        }
    }

    static func setBrightness(_ value: Float) -> Bool {
        let display = CGMainDisplayID()
        let normalized = min(1, max(0, value))
        if let framework, let symbol = dlsym(framework, "DisplayServicesSetBrightness") {
            let set = unsafeBitCast(symbol, to: SetBrightness.self)
            if set(display, normalized) == 0 { return true }
        }

        return withDisplayService { service in
            let key = "brightness" as CFString
            return IODisplaySetFloatParameter(service, 0, key, normalized) == kIOReturnSuccess
        } ?? false
    }

    private static func withDisplayService<T>(_ body: (io_service_t) -> T?) -> T? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator) == kIOReturnSuccess else { return nil }
        defer { IOObjectRelease(iterator) }
        let service = IOIteratorNext(iterator)
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }
        return body(service)
    }
}
