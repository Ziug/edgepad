import AppKit
import SwiftUI

// Lightweight, transient level HUD shown only when EdgePad itself changes
// brightness or volume. Nothing is created or animated until a real change
// happens; the panel and hosting view are built lazily once and reused.
@MainActor
final class LevelHUD {
    enum Control: Equatable {
        case brightness
        case volume

        var name: String {
            switch self {
            case .brightness: "Brightness"
            case .volume: "Volume"
            }
        }

        var icon: String {
            switch self {
            case .brightness: "sun.max.fill"
            case .volume: "speaker.wave.2.fill"
            }
        }

        var tint: Color {
            switch self {
            case .brightness: .yellow
            case .volume: .blue
            }
        }
    }

    static let shared = LevelHUD()

    private let model = HUDModel()
    private var panel: NSPanel?
    private var hideWorkItem: DispatchWorkItem?

    private let hudWidth: CGFloat = 252
    private let hudHeight: CGFloat = 86

    /// Shows (or refreshes) the HUD for a value EdgePad just set, including
    /// quarter-step increments. Resets the one-second hide timer.
    func show(_ control: Control, value: Double, muted: Bool = false) {
        model.control = control
        model.muted = muted && control == .volume
        model.value = min(100, max(0, value))

        let panel = self.panel ?? makePanel()
        position(panel)

        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        }

        hideWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.hide() }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: item)
    }

    private func hide() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0
        }, completionHandler: { panel.orderOut(nil) })
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let x = screen.frame.midX - hudWidth / 2
        let y = screen.visibleFrame.maxY - hudHeight - 8
        panel.setFrame(NSRect(x: x, y: y, width: hudWidth, height: hudHeight), display: true)
    }

    private func makePanel() -> NSPanel {
        let hostingView = NSHostingView(rootView: LevelHUDView(model: model))
        hostingView.frame = NSRect(x: 0, y: 0, width: hudWidth, height: hudHeight)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: hudWidth, height: hudHeight),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.contentView = hostingView
        self.panel = panel
        return panel
    }
}

@MainActor
private final class HUDModel: ObservableObject {
    @Published var control: LevelHUD.Control = .volume
    @Published var value: Double = 0
    @Published var muted: Bool = false
}

private struct LevelHUDView: View {
    @ObservedObject var model: HUDModel

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: iconName)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(model.control.tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 0) {
                    Text(model.control.name.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                    Text(percentText)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }
                Spacer(minLength: 0)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.14))
                    Capsule()
                        .fill(model.control.tint)
                        .frame(width: max(7, geometry.size.width * model.value / 100))
                }
            }
            .frame(height: 6)
        }
        .padding(14)
        .frame(width: 252, height: 86)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var iconName: String {
        if model.control == .volume && model.muted { return "speaker.slash.fill" }
        return model.control.icon
    }

    private var percentText: String {
        if model.value == model.value.rounded() { return "\(Int(model.value))%" }
        var text = String(format: "%.2f", model.value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return "\(text)%"
    }
}
