// Arranque: IqosMonitor.app [--demo]

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false  // continua a vigiar a partir da barra de menus
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.save()
    }
}

@main
struct IqosMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model: AppModel

    init() {
        let m = AppModel(demo: CommandLine.arguments.contains("--demo"))
        _model = State(initialValue: m)
        // Executado fora de um .app (swift run): mostra-se como app normal com Dock.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        Window("IQOS Monitor", id: "main") {
            ContentView(model: model)
                .onAppear { delegate.model = model }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 430, height: 760)

        MenuBarExtra {
            MenuBarPanel(model: model)
        } label: {
            Image(systemName: model.menuBarSymbol)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }
}
