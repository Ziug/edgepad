import SwiftUI

@main
struct EdgePadApp: App {
    var body: some Scene {
        MenuBarExtra("EdgePad", systemImage: "rectangle.split.2x1") {
            MenuBarPanel()
        }
        .menuBarExtraStyle(.window)

        Settings {
            EdgePadWindow()
                .frame(minWidth: 820, minHeight: 600)
        }
        .windowResizability(.contentMinSize)
    }
}
