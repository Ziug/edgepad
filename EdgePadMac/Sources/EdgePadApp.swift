import SwiftUI

@MainActor
@main
struct EdgePadApp: App {
    @StateObject private var runtime: EdgePadRuntime

    init() {
        if let stored = UserDefaults.standard.string(forKey: "edgepad.appearance") {
            NSApplication.shared.appearance = NSAppearance(named: stored == "dark" ? .darkAqua : .aqua)
        }
        let runtime = EdgePadRuntime()
        _runtime = StateObject(wrappedValue: runtime)
        runtime.start()
    }

    var body: some Scene {
        MenuBarExtra("EdgePad", systemImage: "rectangle.split.2x1") {
            MenuBarPanel()
                .environmentObject(runtime)
        }
        .menuBarExtraStyle(.window)

        Settings {
            EdgePadWindow()
                .environmentObject(runtime)
                .frame(minWidth: 820, minHeight: 600)
        }
        .windowResizability(.contentMinSize)
    }
}
