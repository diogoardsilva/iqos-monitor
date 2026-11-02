// Estado da app: dispositivos, ligações, avisos e gravação.
// Faz o papel de MainWindow em iqos_monitor/gui.py, sem a parte visual.

import AppKit
import IqosCore
import Observation
import UserNotifications

@Observable
final class AppModel {
    var settings: Settings
    /// Dispositivos com ligação ativa (para o menu Ligar/Desligar).
    private(set) var linked: Set<String> = []
    var updateAvailable: Release?
    let demo: Bool

    @ObservationIgnored private var links: [String: DeviceLink] = [:]
    @ObservationIgnored private let stateURL: URL
    @ObservationIgnored private var saveWork: DispatchWorkItem?
    @ObservationIgnored private(set) var popup = CornerPopup()
    @ObservationIgnored private var updateTimer: Timer?

    init(demo: Bool) {
        self.demo = demo
        stateURL = Storage.directory().appendingPathComponent(demo ? "demo.json" : "state.json")
        settings = Storage.load(stateURL)
        if demo && settings.devices.isEmpty {
            settings.devices = [
                DeviceState(address: "SIM-01", name: "IQOS ILUMA i PRIME", alias: "IQOS de casa"),
                DeviceState(address: "SIM-02", name: "IQOS ILUMA i ONE", alias: "IQOS do carro"),
            ]
        }
        Notifier.shared.setUp()
        for d in settings.devices { connect(d.id) }
        if !demo {
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.checkUpdates() }
            updateTimer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
                self?.checkUpdates()
            }
        }
    }

    // MARK: Dispositivos

    func device(_ id: String) -> DeviceState? { settings.devices.first { $0.id == id } }

    private func index(_ id: String) -> Int? { settings.devices.firstIndex { $0.id == id } }

    func connect(_ id: String) {
        let cb = LinkCallbacks(
            onBattery: { [weak self] b in self?.update(id) { $0.onBattery(b, now: Date(), lowPct: $1) } },
            onTelemetry: { [weak self] t in self?.update(id) { $0.onTelemetry(t, now: Date(), lowPct: $1) } },
            onStatus: { [weak self] ok, text in self?.status(id, ok, text) })
        let poll = Double(settings.pollSeconds)
        let link: DeviceLink
        if demo {
            link = SimulatedLink(pollSeconds: poll, callbacks: cb)
        } else if let uuid = UUID(uuidString: id) {
            link = IqosLink(id: uuid, pollSeconds: poll, callbacks: cb)
        } else {
            status(id, false, "Identificador inválido; remova e adicione outra vez")
            return
        }
        links[id] = link
        linked.insert(id)
        link.start()
    }

    func toggleConnection(_ id: String) {
        if let link = links.removeValue(forKey: id) {
            linked.remove(id)
            link.stop()
        } else {
            connect(id)
        }
    }

    func add(_ found: [FoundDevice]) {
        for f in found where device(f.id) == nil {
            settings.devices.append(DeviceState(address: f.id, name: f.name))
            connect(f.id)
        }
        scheduleSave()
    }

    func addSimulated() {
        let n = settings.devices.count + 1
        add([FoundDevice(id: String(format: "SIM-%02d", n), name: "IQOS ILUMA i (simulado \(n))", rssi: 0)])
    }

    func rename(_ id: String, to name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let i = index(id), !clean.isEmpty else { return }
        settings.devices[i].alias = clean
        scheduleSave()
    }

    func resetCounts(_ id: String) {
        guard let i = index(id) else { return }
        settings.devices[i].sticksToday = 0
        settings.devices[i].sticksSinceCharge = 0
        scheduleSave()
    }

    func remove(_ id: String) {
        links.removeValue(forKey: id)?.stop()
        linked.remove(id)
        settings.devices.removeAll { $0.id == id }
        scheduleSave()
    }

    func applySettings() {
        for l in links.values { l.pollSeconds = Double(settings.pollSeconds) }
        scheduleSave()
    }

    // MARK: Callbacks

    private func update(_ id: String, _ f: (inout DeviceState, Int) -> [Alert]) {
        guard let i = index(id) else { return }
        let low = settings.lowBatteryPct
        var d = settings.devices[i]
        let alerts = f(&d, low)
        settings.devices[i] = d
        for a in alerts {
            switch a.kind {
            case .holderOut, .holderIn:
                if settings.showPopup { popup.show(d, mode: a.kind == .holderOut ? .out : .back) }
            case .stickEnd where !settings.notifyStickEnd:
                continue
            default:
                Notifier.shared.post(a)
            }
        }
        scheduleSave()
    }

    private func status(_ id: String, _ connected: Bool, _ text: String) {
        guard let i = index(id) else { return }
        let d = settings.devices[i]
        // Nos ONE não há holder: o IQOS liga-se quando é ativado, mostra a janela aí.
        if connected && !d.connected && d.model.onePiece && settings.showPopup {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self, let d = self.device(id) else { return }
                self.popup.show(d, mode: .one)
            }
        }
        settings.devices[i].connected = connected
        settings.devices[i].statusText = text
    }

    // MARK: Gravação e atualizações

    func scheduleSave() {
        saveWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.save() }
        saveWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: w)
    }

    func save() {
        do { try Storage.save(settings, to: stateURL) } catch { log.error("gravar: \(error.localizedDescription)") }
    }

    func checkUpdates(manual: Bool = false) {
        Task { @MainActor [weak self] in
            let rel = try? await Updates.latest()
            guard let self else { return }
            self.updateAvailable = rel
            if manual {
                if let rel {
                    NSWorkspace.shared.open(rel.pageURL)
                } else {
                    Notifier.shared.post(Alert(kind: .charged, title: "Atualizações",
                                               message: "Já tem a versão mais recente (\(Updates.currentVersion))."))
                }
            } else if let rel, self.settings.autoUpdate {
                Notifier.shared.post(Alert(kind: .charged, title: "Atualização disponível",
                                           message: "Versão \(rel.version). Abra o menu ⋯ para a descarregar."))
            }
        }
    }

    var menuBarSymbol: String {
        let pcts = settings.devices.compactMap(\.chargerPct)
        guard let low = pcts.min() else { return "battery.0percent" }
        switch low {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

/// Notificações do macOS (Centro de Notificações).
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()
    private var enabled = false

    func setUp() {
        // UNUserNotificationCenter só funciona dentro de um .app com bundle id.
        guard Bundle.main.bundleIdentifier != nil, !enabled else { return }
        enabled = true
        let c = UNUserNotificationCenter.current()
        c.delegate = self
        c.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(_ a: Alert) {
        guard enabled else {
            NSSound.beep()
            return
        }
        let content = UNMutableNotificationContent()
        content.title = a.title
        content.body = a.message
        content.sound = a.kind == .stickEnd || a.kind == .lowBattery || a.kind == .holderCharge ? .default : nil
        if a.kind == .lowBattery || a.kind == .holderCharge {
            content.interruptionLevel = .timeSensitive
        }
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    // Mostra o aviso mesmo com a app em primeiro plano.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}
