import SwiftUI
import AppKit

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
                    Circle().fill(Color.orange).frame(width: 7, height: 7)
                    Text("Preview mode").font(.system(size: 11)).foregroundStyle(.secondary)
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
        .navigationSplitViewStyle(.balanced)
        .tint(Color(red: 0.30, green: 0.48, blue: 0.94))
    }
}

private struct OverviewPage: View {
    @AppStorage("edgepad.quickMute") private var quickMuteEnabled = true
    @AppStorage("edgepad.haptics") private var hapticsEnabled = true
    @AppStorage("edgepad.normalStep") private var normalStep = 10
    @State private var brightness = 68.0
    @State private var volume = 42.0
    @State private var muted = false

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
                    Label("PREVIEW", systemImage: "sparkle")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.8)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(Color.orange.opacity(0.13), in: Capsule())
                        .foregroundStyle(.orange)
                }

                HStack(alignment: .top, spacing: 22) {
                    VStack(spacing: 12) {
                        ZStack(alignment: .topTrailing) {
                            TrackpadPreview(brightness: $brightness, volume: $volume,
                                            muted: $muted, hapticsEnabled: hapticsEnabled,
                                            normalStep: Double(normalStep))
                            QuickMuteCorner(muted: $muted, enabled: quickMuteEnabled,
                                            hapticsEnabled: hapticsEnabled)
                                .padding(13)
                        }
                        HStack(spacing: 15) {
                            Label("Drag up to increase", systemImage: "arrow.up")
                            Label("Shift–Option for fine steps", systemImage: "command")
                        }
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 14) {
                        Text("CURRENT LEVELS").font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(.secondary)
                        LevelReadout(title: "Brightness", value: brightness, symbol: "sun.max.fill", tint: .yellow)
                        LevelReadout(title: "Volume", value: muted ? 0 : volume, symbol: muted ? "speaker.slash.fill" : "speaker.wave.2.fill", tint: .blue)
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
                    Text("This interactive preview demonstrates the gestures. System-wide touchpad sensing and device control are not connected yet.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(Color.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(28)
        }
    }
}

private struct TrackpadPreview: View {
    @Binding var brightness: Double
    @Binding var volume: Double
    @Binding var muted: Bool
    let hapticsEnabled: Bool
    let normalStep: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 25)
                    .fill(LinearGradient(colors: [Color(nsColor: .controlBackgroundColor), Color(nsColor: .underPageBackgroundColor)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(RoundedRectangle(cornerRadius: 25).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                    .shadow(color: .black.opacity(0.08), radius: 18, y: 8)

                HStack(spacing: 0) {
                    EdgeZone(title: "BRIGHTNESS", symbol: "sun.max.fill", tint: .orange) { delta, fine in
                        brightness = change(brightness, delta: delta, fine: fine)
                    }
                    Spacer(minLength: 12)
                    VStack(spacing: 10) {
                        Image(systemName: "hand.point.up.left.fill")
                            .font(.system(size: 24, weight: .light)).foregroundStyle(.secondary.opacity(0.6))
                        Text("TRACKPAD").font(.system(size: 9, weight: .bold)).tracking(2).foregroundStyle(.tertiary)
                        Text("Try dragging along either edge")
                            .font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    EdgeZone(title: "VOLUME", symbol: muted ? "speaker.slash.fill" : "speaker.wave.2.fill", tint: .blue) { delta, fine in
                        volume = change(volume, delta: delta, fine: fine)
                        if volume > 0 { muted = false }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(height: 265)
    }

    private func change(_ value: Double, delta: Double, fine: Bool) -> Double {
        let increment = fine ? normalStep / 4 : normalStep
        let next = min(100, max(0, value + (delta > 0 ? increment : -increment)))
        guard next != value else { return value }
        if hapticsEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(fine ? .alignment : .levelChange, performanceTime: .now)
        }
        return next
    }
}

private struct EdgeZone: View {
    let title: String
    let symbol: String
    let tint: Color
    let onStep: (Double, Bool) -> Void
    @State private var accumulated = 0.0
    @State private var handledSteps = 0

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
            Text(title).font(.system(size: 8, weight: .bold)).tracking(0.7)
            Capsule().fill(tint.opacity(0.45)).frame(width: 2, height: 64)
            Image(systemName: "arrow.up.arrow.down").font(.system(size: 9, weight: .medium))
        }
        .foregroundStyle(tint)
        .frame(width: 52)
        .frame(maxHeight: .infinity)
        .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(tint.opacity(0.18), lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { value in
                accumulated = value.translation.height
                let steps = Int(abs(accumulated) / 24)
                guard steps > handledSteps else { return }
                let difference = steps - handledSteps
                handledSteps = steps
                let fine = NSEvent.modifierFlags.contains([.shift, .option])
                for _ in 0..<difference { onStep(accumulated < 0 ? 1 : -1, fine) }
            }
            .onEnded { _ in accumulated = 0; handledSteps = 0 })
        .help("Drag up or down to adjust. Hold Shift–Option for fine steps.")
    }
}

private struct QuickMuteCorner: View {
    @Binding var muted: Bool
    let enabled: Bool
    let hapticsEnabled: Bool

    var body: some View {
        if enabled {
            Image(systemName: "speaker.wave.2")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(muted ? .white : .primary.opacity(0.65))
                .frame(width: 28, height: 28)
                .background(muted ? Color.blue : Color(nsColor: .controlBackgroundColor).opacity(0.85), in: Circle())
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                .contentShape(Circle())
                .onTapGesture(count: 2) {
                    muted.toggle()
                    guard hapticsEnabled else { return }
                    let performer = NSHapticFeedbackManager.defaultPerformer
                    performer.perform(.generic, performanceTime: .now)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        performer.perform(.generic, performanceTime: .now)
                    }
                }
                .help("Double-click to toggle mute")
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
    @AppStorage("edgepad.normalStep") private var normalStep = 10
    @AppStorage("edgepad.quickMute") private var quickMuteEnabled = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeading(title: "Controls", subtitle: "Choose how each edge responds to your touch.")
                VStack(alignment: .leading, spacing: 18) {
                    Text("EDGE MAPPING").font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(.secondary)
                    MappingRow(side: "Left edge", symbol: "sun.max.fill", action: "Display brightness", tint: .orange)
                    Divider()
                    MappingRow(side: "Right edge", symbol: "speaker.wave.2.fill", action: "System volume", tint: .blue)
                }
                .padding(18).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 16) {
                    Text("STEP SIZE").font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(.secondary)
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Standard step").font(.system(size: 13, weight: .medium))
                            Text("Each full drag increment").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("Standard step", selection: $normalStep) {
                            Text("5%").tag(5); Text("10%").tag(10); Text("15%").tag(15)
                        }.labelsHidden().frame(width: 90)
                    }
                    Divider()
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Fine step").font(.system(size: 13, weight: .medium))
                            Text("One quarter of the standard step").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Double(normalStep) / 4, specifier: normalStep % 4 == 0 ? "%.0f" : "%.2g")%")
                            .font(.system(size: 12, weight: .medium, design: .rounded)).monospacedDigit()
                    }
                    Divider()
                    Toggle(isOn: $quickMuteEnabled) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Quick Mute").font(.system(size: 13, weight: .medium))
                            Text("Double-tap the top-right trackpad corner").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                }
                .toggleStyle(.switch)
                .padding(18).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))

                NoteCard(text: "In this preview, values are illustrative. Device-level controls will be wired when system integration is added.")
            }
            .padding(28)
        }
    }
}

private struct HapticsPage: View {
    @AppStorage("edgepad.haptics") private var hapticsEnabled = true

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeading(title: "Haptic feedback", subtitle: "A distinct tap confirms each adjustment on a supported Force Touch trackpad.")
            VStack(spacing: 0) {
                HapticRow(title: "Standard step", detail: "Light tap", symbol: "hand.tap.fill", pattern: .levelChange, enabled: hapticsEnabled)
                Divider().padding(.leading, 52)
                HapticRow(title: "Fine step", detail: "Lighter alignment tap", symbol: "circle.lefthalf.filled", pattern: .alignment, enabled: hapticsEnabled)
                Divider().padding(.leading, 52)
                HapticRow(title: "Quick Mute", detail: "Two quick taps", symbol: "speaker.slash.fill", pattern: .generic, enabled: hapticsEnabled)
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
            NoteCard(text: "Try the gesture preview on Overview. Haptic strength is controlled by macOS and the trackpad hardware.")
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
                let performer = NSHapticFeedbackManager.defaultPerformer
                performer.perform(pattern, performanceTime: .now)
                if title == "Quick Mute" {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        performer.perform(.generic, performanceTime: .now)
                    }
                }
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

struct MenuBarPanel: View {
    @State private var brightness = 68.0
    @State private var volume = 42.0
    @State private var muted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("EdgePad", systemImage: "rectangle.split.2x1.fill").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("PREVIEW").font(.system(size: 9, weight: .bold)).foregroundStyle(.orange)
            }
            Divider()
            Label("Brightness · \(Int(brightness))%", systemImage: "sun.max.fill").font(.system(size: 11))
            Slider(value: $brightness, in: 0...100)
            Label(muted ? "Volume · Muted" : "Volume · \(Int(volume))%", systemImage: muted ? "speaker.slash.fill" : "speaker.wave.2.fill").font(.system(size: 11))
            Slider(value: $volume, in: 0...100).disabled(muted)
            Button(muted ? "Unmute" : "Mute") { muted.toggle() }
                .buttonStyle(.bordered).controlSize(.small)
            Divider()
            Text("Preview values only · device control not connected")
                .font(.system(size: 9)).foregroundStyle(.secondary)
            Divider()
            SettingsLink {
                Label("Settings…", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit EdgePad", systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(width: 230)
    }
}
