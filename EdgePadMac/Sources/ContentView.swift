import SwiftUI
import AppKit
import Combine
import ServiceManagement

private enum EdgePage: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case controls = "Controls"
    case haptics = "Haptics"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .overview: "rectangle.split.2x1"
        case .controls: "slider.horizontal.3"
        case .haptics: "waveform"
        }
    }
}

struct EdgePadWindow: View {
    @EnvironmentObject private var runtime: EdgePadRuntime
    @State private var selection: EdgePage? = .overview

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "rectangle.split.2x1.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("EdgePad").font(.system(size: 14, weight: .semibold))
                        Text("Touchpad controls").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 12)
                .padding(.bottom, 18)

                ForEach(EdgePage.allCases) { page in
                    Button {
                        selection = page
                    } label: {
                        Label(page.rawValue, systemImage: page.symbol)
                            .font(.system(size: 13, weight: selection == page ? .medium : .regular))
                            .foregroundStyle(selection == page ? Color.primary : Color.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(selection == page ? Color.accentColor.opacity(0.11) : .clear,
                                        in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                HStack(spacing: 8) {
                    Circle().fill(runtime.isListening ? Color.green : Color.orange).frame(width: 7, height: 7)
                    Text(runtime.inputStatus).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
            .padding(.horizontal, 10)
            .frame(minWidth: 190)
            .background(Color(nsColor: .controlBackgroundColor))
        } detail: {
            Group {
                switch selection ?? .overview {
                case .overview: OverviewPage()
                case .controls: ControlsPage()
                case .haptics: HapticsPage()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .onAppear { runtime.refreshSystemValues() }
        .navigationSplitViewStyle(.balanced)
        .tint(Color(red: 0.30, green: 0.48, blue: 0.94))
    }
}

private struct OverviewPage: View {
    @EnvironmentObject private var runtime: EdgePadRuntime
    @AppStorage("edgepad.quickMute") private var quickMuteEnabled = true
    @AppStorage("edgepad.haptics") private var hapticsEnabled = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your touchpad, with two new edges.")
                            .font(.system(size: 25, weight: .semibold, design: .rounded))
                        Text("Adjust brightness and volume without moving the pointer.")
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label(runtime.isListening ? "LIVE" : "PAUSED", systemImage: runtime.isListening ? "waveform" : "pause.fill")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.8)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background((runtime.isListening ? Color.green : Color.orange).opacity(0.13), in: Capsule())
                        .foregroundStyle(runtime.isListening ? .green : .orange)
                }

                HStack(alignment: .top, spacing: 22) {
                    VStack(spacing: 12) {
                        ZStack(alignment: .topTrailing) {
                            TrackpadPreview()
                            QuickMuteCorner(muted: runtime.isMuted, enabled: quickMuteEnabled)
                                .padding(13)
                        }
                        HStack(spacing: 15) {
                            Label("Slide up to increase", systemImage: "arrow.up")
                            Label("Shift–Option for fine steps", systemImage: "command")
                        }
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 14) {
                        Text("CURRENT LEVELS").font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(.secondary)
                        LevelReadout(title: "Brightness", value: runtime.brightness, symbol: "sun.max.fill", tint: .yellow)
                        LevelReadout(title: "Volume", value: runtime.isMuted ? 0 : runtime.volume, symbol: runtime.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", tint: .blue)
                        Divider().padding(.vertical, 2)
                        HStack(spacing: 9) {
                            Image(systemName: "hand.tap.fill").foregroundStyle(.secondary)
                            Text("Haptic feedback")
                            Spacer()
                            Toggle("Haptic feedback", isOn: $hapticsEnabled).labelsHidden().toggleStyle(.switch)
                        }
                        .font(.system(size: 12))
                        HStack(spacing: 9) {
                            Image(systemName: "speaker.slash.fill").foregroundStyle(.secondary)
                            Text("Quick Mute")
                            Spacer()
                            Toggle("Quick Mute", isOn: $quickMuteEnabled).labelsHidden().toggleStyle(.switch)
                        }
                        .font(.system(size: 12))
                        Text("Double-tap the upper-right corner of the trackpad.")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .frame(width: 220, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
                }

                HStack(spacing: 12) {
                    Image(systemName: "info.circle.fill").foregroundStyle(.blue)
                    Text(runtime.inputStatus)
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(Color.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                if let controlError = runtime.controlError {
                    NoteCard(text: controlError)
                }
                if !runtime.isTouchInputAuthorized {
                    Button("Allow Input Monitoring for touchpad") { runtime.requestTouchInputAccess() }
                        .font(.system(size: 11))
                }
                if runtime.isListening && !runtime.isPointerMonitoringAvailable {
                    Button("Allow Device Control & Data Access", action: runtime.requestPointerAccess)
                        .font(.system(size: 11))
                }
            }
            .padding(28)
        }
    }
}

private struct TrackpadPreview: View {
    @EnvironmentObject private var runtime: EdgePadRuntime

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 25)
                    .fill(LinearGradient(colors: [Color(nsColor: .controlBackgroundColor), Color(nsColor: .underPageBackgroundColor)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(RoundedRectangle(cornerRadius: 25).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                    .shadow(color: .black.opacity(0.08), radius: 18, y: 8)

                HStack(spacing: 0) {
                    EdgeZone(title: "BRIGHTNESS", symbol: "sun.max.fill", tint: .orange,
                             active: runtime.activeEdge == .brightness)
                    Spacer(minLength: 12)
                    VStack(spacing: 10) {
                        Image(systemName: runtime.isListening ? "hand.point.up.left.fill" : "hand.raised.fill")
                            .font(.system(size: 24, weight: .light)).foregroundStyle(.secondary.opacity(0.6))
                        Text(runtime.isListening ? "TRACKPAD LIVE" : "TRACKPAD PAUSED").font(.system(size: 9, weight: .bold)).tracking(2).foregroundStyle(.tertiary)
                        Text("Slide a finger along either edge")
                            .font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    EdgeZone(title: "VOLUME", symbol: "speaker.wave.2.fill", tint: .blue,
                             active: runtime.activeEdge == .volume)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(height: 265)
    }

}

private struct EdgeZone: View {
    let title: String
    let symbol: String
    let tint: Color
    let active: Bool

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
            Text(title).font(.system(size: 8, weight: .bold)).tracking(0.7)
            Capsule().fill(tint.opacity(0.45)).frame(width: 2, height: 64)
            Image(systemName: "arrow.up.arrow.down").font(.system(size: 9, weight: .medium))
        }
        .foregroundStyle(active ? .white : tint)
        .frame(width: 52)
        .frame(maxHeight: .infinity)
        .background(active ? tint : tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(tint.opacity(0.24), lineWidth: 1))
    }
}

private struct QuickMuteCorner: View {
    let muted: Bool
    let enabled: Bool

    var body: some View {
        if enabled {
            Image(systemName: "speaker.wave.2")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(muted ? .white : .primary.opacity(0.65))
                .frame(width: 28, height: 28)
                .background(muted ? Color.blue : Color(nsColor: .controlBackgroundColor).opacity(0.85), in: Circle())
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                .contentShape(Circle())
                .help("Quick Mute: double-tap this trackpad corner")
        }
    }
}

private struct LevelReadout: View {
    let title: String
    let value: Double
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: symbol).font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(Int(value))%").font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule().fill(tint).frame(width: geo.size.width * value / 100)
                }
            }
            .frame(height: 5)
        }
    }
}

private struct ControlsPage: View {
    @EnvironmentObject private var runtime: EdgePadRuntime
    @AppStorage("edgepad.enabled") private var controlsEnabled = true
    @AppStorage("edgepad.quickMute") private var quickMuteEnabled = true
    @AppStorage("edgepad.swapSides") private var swapSides = false
    @AppStorage("edgepad.bottomQuarterOnly") private var bottomQuarterOnly = false
    @AppStorage("edgepad.requireModifier") private var requireModifier = false
    @AppStorage("edgepad.mediaStrip") private var mediaStripEnabled = true
    @AppStorage("edgepad.mediaTapPlayPause") private var mediaTapEnabled = false
    @AppStorage("edgepad.freezeCursor") private var freezeCursor = true
    @AppStorage("edgepad.fineControl") private var fineControl = true
    @AppStorage("edgepad.edgeWidth") private var edgeWidth = 5.0
    @AppStorage("edgepad.sensitivity") private var sensitivity = 1.0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeading(title: "Controls", subtitle: "Choose how each edge responds to your touch.")
                Toggle(isOn: $controlsEnabled) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Enable EdgePad").font(.system(size: 13, weight: .medium))
                        Text("Listen for edge touches system-wide").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .padding(16).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                .onChange(of: controlsEnabled) { _, enabled in runtime.setEnabled(enabled) }

                VStack(alignment: .leading, spacing: 18) {
                    Text("EDGE GESTURES").font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(.secondary)
                    PreferenceToggle(symbol: "arrow.left.arrow.right", title: "Swap Sides", subtitle: swapSides ? "Left: Volume · Right: Brightness" : "Left: Brightness · Right: Volume", isOn: $swapSides)
                    Divider()
                    PreferenceToggle(symbol: "rectangle.bottomthird.inset.filled", title: "Bottom Quarter Only", subtitle: "Ignore touches above the lower 25%", isOn: $bottomQuarterOnly)
                    Divider()
                    PreferenceToggle(symbol: "option", title: "Require Fn or ⌥", subtitle: "Only start an edge slide while held", isOn: $requireModifier)
                    Divider()
                    PreferenceToggle(symbol: "speaker.slash.fill", title: "Quick Mute", subtitle: "Double-tap the top-right corner", isOn: $quickMuteEnabled)
                    Divider()
                    PreferenceToggle(symbol: "forward.fill", title: "Media Strip", subtitle: "Swipe the bottom edge to skip songs", isOn: $mediaStripEnabled)
                    if mediaStripEnabled {
                        PreferenceToggle(symbol: "playpause.fill", title: "Tap to Play or Pause", subtitle: "Clicks near the edge can set it off", isOn: $mediaTapEnabled)
                            .padding(.leading, 20)
                    }
                }
                .padding(18).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 18) {
                    Text("WHILE SLIDING").font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(.secondary)
                    PreferenceToggle(symbol: "cursorarrow", title: "Freeze Cursor", subtitle: runtime.isPointerMonitoringAvailable ? "Pointer stays put while sliding" : "Device Control & Data Access is required", isOn: $freezeCursor)
                        .onChange(of: freezeCursor) { _, enabled in runtime.setFreezeCursor(enabled) }
                    if freezeCursor && !runtime.isPointerMonitoringAvailable {
                        Button("Request Device Control & Data Access") { runtime.requestPointerAccess() }
                            .font(.system(size: 11))
                    }
                    Divider()
                    PreferenceToggle(symbol: "sun.max", title: "Fine Control", subtitle: "Hold ⇧⌥ for one-quarter steps", isOn: $fineControl)
                }
                .padding(18).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 16) {
                    Text("SENSITIVITY").font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(.secondary)
                    SliderSetting(title: "Sensitivity", value: $sensitivity, range: 0.5...2.0, valueText: String(format: "%.1f×", sensitivity))
                    Divider()
                    SliderSetting(title: "Edge Width", value: $edgeWidth, range: 2...20, valueText: "\(Int(edgeWidth))%")
                    Divider()
                    Text("A standard notch is 1/16 of the range. Holding Shift–Option divides that into quarter steps, matching the Mac keyboard controls.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(18).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 10) {
                    NoteCard(text: "Global touch sensing uses Apple’s private MultitouchSupport interface. macOS updates can change this interface.")
                    if !runtime.isTouchInputAuthorized {
                        Button("Allow Input Monitoring for touchpad") { runtime.requestTouchInputAccess() }
                            .font(.system(size: 11))
                    }
                    Text(runtime.isListening
                         ? "Touch stream: \(runtime.touchCount) active · \(runtime.lastTouchPoint.map { String(format: "x %.2f / y %.2f", $0.x, $0.y) } ?? "move a finger to check")"
                         : runtime.inputStatus)
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    Text("Device Control & Data Access: \(runtime.isAccessibilityTrusted ? "granted" : "not granted") · cursor filter: \(runtime.isPointerMonitoringAvailable ? "ready" : "inactive")")
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    if let controlError = runtime.controlError {
                        NoteCard(text: controlError)
                    }
                    Button("Reconnect to trackpad") { runtime.start() }
                        .font(.system(size: 11))
                }

                DiagnosticsCard()
            }
            .padding(28)
        }
        .onAppear { runtime.setDiagnosticsVisible(true) }
        .onDisappear { runtime.setDiagnosticsVisible(false) }
    }
}

private struct DiagnosticsCard: View {
    @EnvironmentObject private var runtime: EdgePadRuntime
    @State private var snapshot: DiagnosticsSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("DIAGNOSTICS")
                    .font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(.secondary)
                Spacer()
                Button("Reset counters") {
                    runtime.resetDiagnostics()
                    snapshot = runtime.diagnosticsSnapshot()
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.blue)
            }
            Text(headline).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            Text(detail).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            Text(totals).font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
            NoteCard(text: "CPU % is instantaneous processor load; Energy Impact weights total power draw (GPU, display, sensors). With fingers off the glass every rate should read 0 and Activity Monitor should show flat Energy Impact. Compare idle, ordinary touch and edge sliding using Reset, then check both columns in Activity Monitor — impact, not raw %, is the number that maps to battery.")
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .onAppear { snapshot = runtime.diagnosticsSnapshot() }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            snapshot = runtime.diagnosticsSnapshot()
        }
    }

    private var headline: String {
        guard let s = snapshot else { return "Callbacks —/s · processed —/s · idle dropped —/s" }
        return String(format: "Callbacks %.0f/s · processed %.0f/s · idle dropped %.0f/s",
                      s.framesPerSecond, s.processedPerSecond, s.idleDroppedPerSecond)
    }

    private var detail: String {
        guard let s = snapshot else { return "Writes —/s · haptics —/s · cursor warps —/s · media —/s" }
        return String(format: "Writes %.1f/s · haptics %.1f/s · warps %.0f/s · media %.0f/s",
                      s.writesPerSecond, s.hapticsPerSecond, s.warpsPerSecond, s.mediaKeysPerSecond)
    }

    private var totals: String {
        guard let s = snapshot else { return "Total since launch: — callbacks · — processed · — media keys" }
        return "Total since launch: \(s.totalHardwareFrames) callbacks · \(s.totalProcessedFrames) processed · \(s.totalMediaKeys) media keys"
    }
}

private struct HapticsPage: View {
    @EnvironmentObject private var runtime: EdgePadRuntime
    @AppStorage("edgepad.haptics") private var hapticsEnabled = true

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeading(title: "Haptic feedback", subtitle: "A distinct tap confirms each adjustment on a supported Force Touch trackpad.")
            VStack(spacing: 0) {
                HapticRow(title: "Standard step", detail: "Light tap", symbol: "hand.tap.fill", pattern: .levelChange, enabled: hapticsEnabled)
                Divider().padding(.leading, 52)
                HapticRow(title: "Fine step", detail: "Lighter alignment tap", symbol: "circle.lefthalf.filled", pattern: .alignment, enabled: hapticsEnabled)
                Divider().padding(.leading, 52)
                HapticRow(title: "Quick Mute", detail: "Two quick taps", symbol: "speaker.slash.fill", pattern: .generic, enabled: hapticsEnabled) {
                    runtime.previewMuteHaptic()
                }
            }
            .padding(.horizontal, 16)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Haptic feedback").font(.system(size: 13, weight: .medium))
                    Text("Use the trackpad’s built-in haptic engine").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Haptic feedback", isOn: $hapticsEnabled).labelsHidden()
            }
            .padding(16).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            NoteCard(text: "Haptic strength is controlled by macOS and the trackpad hardware.")
            Spacer()
        }
        .padding(28)
    }
}

private struct HapticRow: View {
    let title: String
    let detail: String
    let symbol: String
    let pattern: NSHapticFeedbackManager.FeedbackPattern
    let enabled: Bool
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(.blue).frame(width: 28, height: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Play") {
                guard enabled else { return }
                if let action {
                    action()
                    return
                }
                let performer = NSHapticFeedbackManager.defaultPerformer
                performer.perform(pattern, performanceTime: .now)
            }
            .buttonStyle(.bordered).controlSize(.small)
            .disabled(!enabled)
        }
        .padding(.vertical, 12)
    }
}

private struct MappingRow: View {
    let side: String
    let symbol: String
    let action: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(tint)
                .frame(width: 34, height: 34).background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(side).font(.system(size: 12, weight: .medium))
                Text(action).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "arrow.up.arrow.down").font(.system(size: 11, weight: .medium)).foregroundStyle(.tertiary)
        }
    }
}

private struct PageHeading: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 25, weight: .semibold, design: .rounded))
            Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
    }
}

private struct NoteCard: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "info.circle.fill")
            .font(.system(size: 11)).foregroundStyle(.secondary)
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }
}

private let panelPurple = Color(red: 0.435, green: 0.341, blue: 0.941)

private func showEdgePadAbout() {
    let alert = NSAlert()
    alert.alertStyle = .informational
    alert.messageText = "EdgePad \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")"
    alert.informativeText = "Touchpad edge controls for brightness and volume. Brightness and volume are set directly, so macOS’s HUDs are not shown.\n\nUses Apple’s private MultitouchSupport framework, which may change with system updates."
    alert.addButton(withTitle: "OK")
    NSApp.activate(ignoringOtherApps: true)
    alert.runModal()
}

private enum PanelPage {
    case main
    case settings
}

private enum PanelBadge {
    case purple
    case grey

    var fill: Color {
        switch self {
        case .purple: panelPurple
        case .grey: Color.primary.opacity(0.08)
        }
    }

    var icon: Color {
        switch self {
        case .purple: .white
        case .grey: .primary.opacity(0.75)
        }
    }
}

private struct IconBadge: View {
    let symbol: String
    let badge: PanelBadge

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(badge.icon)
            .frame(width: 34, height: 34)
            .background(badge.fill, in: Circle())
    }
}

private struct PanelRow<Trailing: View>: View {
    let symbol: String
    let badge: PanelBadge
    let title: String
    let subtitle: String?
    let trailing: Trailing

    init(symbol: String, badge: PanelBadge, title: String, subtitle: String? = nil,
         @ViewBuilder trailing: () -> Trailing) {
        self.symbol = symbol
        self.badge = badge
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(symbol: symbol, badge: badge)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .semibold))
                if let subtitle {
                    Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.vertical, 5)
    }
}

private struct PanelSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .tracking(1)
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                content
            }
        }
    }
}

private struct LevelCard: View {
    let brightness: Double
    let volume: Double
    let isMuted: Bool

    var body: some View {
        HStack(spacing: 0) {
            Capsule().fill(Color.orange).frame(width: 5).frame(maxHeight: 80)
            HStack(spacing: 0) {
                levelCell(
                    value: brightness,
                    label: "BRIGHTNESS",
                    symbol: "sun.max.fill",
                    tint: .orange,
                    labelFirst: true
                )
                Spacer(minLength: 0)
                levelCell(
                    value: volume,
                    label: "VOLUME",
                    symbol: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    tint: .blue,
                    labelFirst: false
                )
            }
            .padding(.horizontal, 12)
            Capsule().fill(Color.blue).frame(width: 5).frame(maxHeight: 80)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 16)
        .frame(height: 112)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private func levelCell(value: Double, label: String, symbol: String, tint: Color, labelFirst: Bool) -> some View {
        VStack(alignment: labelFirst ? .leading : .trailing, spacing: 2) {
            HStack(spacing: 6) {
                if labelFirst {
                    Image(systemName: symbol).foregroundStyle(tint)
                    Text(label).foregroundStyle(.secondary)
                } else {
                    Text(label).foregroundStyle(.secondary)
                    Image(systemName: symbol).foregroundStyle(tint)
                }
            }
            .font(.system(size: 10, weight: .bold)).tracking(1.1)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(Int(value))")
                    .font(.system(size: 46, weight: .light, design: .rounded))
                    .monospacedDigit()
                Text("%")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct DottedSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    private let dotCount = 12
    private let thumbSize: CGFloat = 20

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let fraction = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(0..<dotCount, id: \.self) { index in
                        Circle()
                            .fill(dotColor(index: index, fraction: fraction))
                            .frame(width: 4, height: 4)
                        if index < dotCount - 1 { Spacer(minLength: 0) }
                    }
                }
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.08), lineWidth: 1))
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                    .offset(x: fraction * max(0, width - thumbSize))
            }
            .frame(height: thumbSize)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        value = value(from: gesture.location.x, width: width)
                    }
            )
        }
        .frame(height: thumbSize)
    }

    private func dotColor(index: Int, fraction: CGFloat) -> Color {
        let dotFraction = CGFloat(index) / CGFloat(dotCount - 1)
        return dotFraction <= fraction ? panelPurple : Color.primary.opacity(0.16)
    }

    private func value(from x: CGFloat, width: CGFloat) -> Double {
        let usable = max(width - thumbSize, 1)
        let clamped = min(max(x - thumbSize / 2, 0), usable)
        let fraction = Double(clamped / usable)
        let raw = range.lowerBound + fraction * (range.upperBound - range.lowerBound)
        let snapped = (raw / step).rounded() * step
        return min(range.upperBound, max(range.lowerBound, snapped))
    }
}

private struct EllipsisMenu: View {
    let onResetDiagnostics: () -> Void

    var body: some View {
        Menu {
            Button("About EdgePad") { showEdgePadAbout() }
            Button("Reset Diagnostics Counters") { onResetDiagnostics() }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(Color.primary.opacity(0.07), in: Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

private struct PanelPowerButton: View {
    var body: some View {
        Button { NSApp.terminate(nil) } label: {
            Image(systemName: "power")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .help("Quit EdgePad")
    }
}

struct MenuBarPanel: View {
    @EnvironmentObject private var runtime: EdgePadRuntime

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    @AppStorage("edgepad.hapticsStrength") private var hapticsStrength = "strong"
    @AppStorage("edgepad.quickMute") private var quickMuteEnabled = true
    @AppStorage("edgepad.mediaStrip") private var mediaStripEnabled = true
    @AppStorage("edgepad.mediaTapPlayPause") private var mediaTapEnabled = false
    @AppStorage("edgepad.freezeCursor") private var freezeCursor = true
    @AppStorage("edgepad.fineControl") private var fineControl = true
    @AppStorage("edgepad.swapSides") private var swapSides = false
    @AppStorage("edgepad.bottomQuarterOnly") private var bottomQuarterOnly = false
    @AppStorage("edgepad.requireModifier") private var requireModifier = false
    @AppStorage("edgepad.sensitivity") private var sensitivity = 1.0
    @AppStorage("edgepad.edgeWidth") private var edgeWidth = 5.0

    @State private var page: PanelPage = .main
    @State private var mediaExpanded = true
    @State private var appearance = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? "dark" : "light"
    @State private var launchAtLogin = false

    var body: some View {
        Group {
            if page == .main { mainPage } else { settingsPage }
        }
        .frame(width: 340)
        .background(Color(nsColor: .underPageBackgroundColor))
        .onAppear {
            runtime.refreshSystemValues()
            if let stored = UserDefaults.standard.string(forKey: "edgepad.appearance") {
                appearance = stored
            }
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private var mainPage: some View {
        VStack(spacing: 12) {
            LevelCard(
                brightness: runtime.brightness,
                volume: runtime.isMuted ? 0 : runtime.volume,
                isMuted: runtime.isMuted
            )

            PanelRow(symbol: "hand.tap.fill", badge: .purple,
                     title: "Haptic Feedback", subtitle: "Clicks as you slide") {
                Menu {
                    Button("Light") { hapticsStrength = "light" }
                    Button("Medium") { hapticsStrength = "medium" }
                    Button("Strong") { hapticsStrength = "strong" }
                } label: {
                    HStack(spacing: 5) {
                        Text(hapticsStrength.capitalized)
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(panelPurple)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(panelPurple.opacity(0.13), in: Capsule())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }

            PanelRow(symbol: "speaker.slash.fill", badge: quickMuteEnabled ? .purple : .grey,
                     title: "Quick Mute", subtitle: "Double-tap the top-right corner") {
                Toggle("Quick Mute", isOn: $quickMuteEnabled)
                    .labelsHidden().toggleStyle(.switch).tint(panelPurple)
            }

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    IconBadge(symbol: "forward.fill", badge: mediaStripEnabled ? .purple : .grey)
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { mediaExpanded.toggle() }
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 4) {
                                Text("Media Strip").font(.system(size: 13, weight: .semibold))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .rotationEffect(.degrees(mediaExpanded ? 0 : -90))
                            }
                            Text("Swipe the bottom edge to skip songs")
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                    Toggle("Media Strip", isOn: $mediaStripEnabled)
                        .labelsHidden().toggleStyle(.switch).tint(panelPurple)
                }
                .padding(.vertical, 5)

                if mediaExpanded {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Tap to Play or Pause").font(.system(size: 12, weight: .medium))
                            Text("Clicks near the edge can set it off")
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Toggle("Tap to Play or Pause", isOn: $mediaTapEnabled)
                            .labelsHidden().toggleStyle(.switch).tint(panelPurple)
                    }
                    .padding(.leading, 46)
                    .padding(.vertical, 4)
                }
            }

            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    IconBadge(symbol: "gauge", badge: .grey)
                    Text("Sensitivity").font(.system(size: 13))
                    Spacer()
                    Text(String(format: "%.1f×", sensitivity))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary).monospacedDigit()
                }
                DottedSlider(value: $sensitivity, range: 0.5...2.0, step: 0.1)
            }

            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    IconBadge(symbol: "arrow.left.arrow.right", badge: .grey)
                    Text("Edge Width").font(.system(size: 13))
                    Spacer()
                    Text("\(Int(edgeWidth))%")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary).monospacedDigit()
                }
                DottedSlider(value: $edgeWidth, range: 2...20, step: 1)
            }

            if !runtime.isTouchInputAuthorized {
                Button("Allow Input Monitoring") { runtime.requestTouchInputAccess() }
                    .font(.system(size: 11))
            }
            if freezeCursor && !runtime.isPointerMonitoringAvailable {
                Button("Request Device Control & Data Access") { runtime.requestPointerAccess() }
                    .font(.system(size: 11))
            }
            if let controlError = runtime.controlError {
                Text(controlError).font(.system(size: 9)).foregroundStyle(.red)
            }

            HStack {
                Button { page = .settings } label: {
                    Label("Settings", systemImage: "gearshape")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
                Spacer()
                EllipsisMenu(onResetDiagnostics: { runtime.resetDiagnostics() })
                PanelPowerButton()
            }
            .padding(.top, 4)
        }
        .padding(14)
    }

    private var settingsPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            PanelSection("Edge Gestures") {
                PanelRow(symbol: "arrow.left.arrow.right", badge: swapSides ? .purple : .grey,
                         title: "Swap Sides", subtitle: "Left: Brightness · Right: Volume") {
                    Toggle("Swap Sides", isOn: $swapSides)
                        .labelsHidden().toggleStyle(.switch).tint(panelPurple)
                }
                PanelRow(symbol: "rectangle.bottomthird.inset.filled", badge: bottomQuarterOnly ? .purple : .grey,
                         title: "Bottom Quarter Only", subtitle: "Ignore touches above the lower 25%") {
                    Toggle("Bottom Quarter Only", isOn: $bottomQuarterOnly)
                        .labelsHidden().toggleStyle(.switch).tint(panelPurple)
                }
                PanelRow(symbol: "option", badge: requireModifier ? .purple : .grey,
                         title: "Require Fn or ⌥", subtitle: "Only slide while holding a modifier") {
                    Toggle("Require Fn or Option", isOn: $requireModifier)
                        .labelsHidden().toggleStyle(.switch).tint(panelPurple)
                }
            }

            PanelSection("While Sliding") {
                PanelRow(symbol: "cursorarrow", badge: freezeCursor ? .purple : .grey,
                         title: "Freeze Cursor",
                         subtitle: runtime.isPointerMonitoringAvailable ? "Pointer stays put while sliding" : "Allow Device Control & Data Access") {
                    Toggle("Freeze Cursor", isOn: $freezeCursor)
                        .labelsHidden().toggleStyle(.switch).tint(panelPurple)
                        .onChange(of: freezeCursor) { _, enabled in runtime.setFreezeCursor(enabled) }
                }
                PanelRow(symbol: "sun.max", badge: fineControl ? .purple : .grey,
                         title: "Fine Control", subtitle: "Hold ⇧⌥ for quarter steps") {
                    Toggle("Fine Control", isOn: $fineControl)
                        .labelsHidden().toggleStyle(.switch).tint(panelPurple)
                }
            }

            PanelSection("General") {
                PanelRow(symbol: "circle.lefthalf.filled", badge: .grey, title: "Appearance") {
                    Picker("Appearance", selection: $appearance) {
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .onChange(of: appearance) { _, value in
                        UserDefaults.standard.set(value, forKey: "edgepad.appearance")
                        NSApp.appearance = NSAppearance(named: value == "dark" ? .darkAqua : .aqua)
                    }
                }
                PanelRow(symbol: "power", badge: launchAtLogin ? .purple : .grey, title: "Open at Login") {
                    Toggle("Open at Login", isOn: Binding(
                        get: { launchAtLogin },
                        set: { enabled in setLaunchAtLogin(enabled) }
                    ))
                    .labelsHidden().toggleStyle(.switch).tint(panelPurple)
                }
            }

            SettingsLink {
                Text("Open full settings…")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)

            HStack {
                Button { page = .main } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                        Text("Back").font(.system(size: 13, weight: .semibold))
                    }
                }
                .buttonStyle(.plain)
                .frame(minWidth: 64, alignment: .leading)
                Spacer()
                Text("Version \(Self.appVersion)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                EllipsisMenu(onResetDiagnostics: { runtime.resetDiagnostics() })
                PanelPowerButton()
            }
            .padding(.top, 4)
        }
        .padding(14)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Registration can require approval in System Settings; reflect reality.
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

private struct PreferenceToggle: View {
    let symbol: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 14, weight: .medium)).foregroundStyle(.primary)
                .frame(width: 32, height: 32).background(Color.primary.opacity(0.07), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Toggle(title, isOn: $isOn).labelsHidden().controlSize(.small)
        }
    }
}

private struct SliderSetting: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let valueText: String

    var body: some View {
        VStack(spacing: 7) {
            HStack {
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer()
                Text(valueText).font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
            }
            Slider(value: $value, in: range)
        }
    }
}
