// Arranque: IqosMonitor.app [--demo]
// App só da barra de menus (LSUIElement): sem ícone no Dock nem janela principal.

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?

    func applicationWillTerminate(_ notification: Notification) {
        model?.save()
    }

    // A barra de menus pode esconder o ícone; abrir a app outra vez mostra as Definições.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NSApp.activate()
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        return false
    }
}

@main
struct IqosMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model: AppModel

    init() {
        let m = AppModel(demo: CommandLine.arguments.contains("--demo"))
        _model = State(initialValue: m)
        // Fora de um .app (swift run) não há Info.plist com LSUIElement.
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuPanel(model: model)
                .onAppear { delegate.model = model }
        } label: {
            Image(systemName: model.menuBarSymbol)
                .accessibilityLabel("IQOS Monitor")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }
}
