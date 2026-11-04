// Arranque: IqosMonitor.app [--demo]
// App só da barra de menus (LSUIElement): sem ícone no Dock nem janela principal.

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel(demo: CommandLine.arguments.contains("--demo"))
    private var status: StatusPanel?
    private lazy var settingsWindow = SettingsWindow(model: model)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Fora de um .app (swift run) não há Info.plist com LSUIElement.
        NSApp.setActivationPolicy(.accessory)
        status = StatusPanel(model: model) { [weak self] in self?.settingsWindow.show() }
        if CommandLine.arguments.contains("--updated") {
            Notifier.shared.post(.init(kind: .charged, title: "IQOS Monitor",
                                       message: "Atualizado para a versão \(Updates.currentVersion)."))
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.save()
    }

    // A barra de menus pode esconder o ícone; abrir a app outra vez mostra as Definições.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow.show()
        return false
    }
}

@main
struct IqosMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings {
            SettingsView(model: delegate.model)
        }
    }
}
