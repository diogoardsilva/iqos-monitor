// Ligação BLE aos IQOS com CoreBluetooth.
// Mesmo comportamento de iqos_monitor/ble.py: notificações de bateria,
// pedidos SCP de telemetria a cada N segundos e reconexão automática.
// Tudo corre na fila principal (CBCentralManager com queue nil).

import CoreBluetooth
import IqosCore
import os

let log = Logger(subsystem: "pt.diogoardsilva.IqosMonitor", category: "ble")

struct LinkCallbacks {
    var onBattery: (BatteryStatus) -> Void
    var onTelemetry: (Telemetry) -> Void
    var onStatus: (_ connected: Bool, _ text: String) -> Void
}

protocol DeviceLink: AnyObject {
    var pollSeconds: Double { get set }
    func start()
    func stop()
}

struct FoundDevice: Identifiable, Hashable {
    var id: String  // identificador do CoreBluetooth (o macOS não mostra o MAC)
    var name: String
    var rssi: Int
}

final class Bluetooth: NSObject, CBCentralManagerDelegate {
    static let shared = Bluetooth()

    private(set) var central: CBCentralManager!
    private var links: [UUID: IqosLink] = [:]
    private var waiters: [() -> Void] = []
    private var onFound: ((FoundDevice) -> Void)?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    var stateText: String? {
        switch central.state {
        case .poweredOn: return nil
        case .poweredOff: return "O Bluetooth está desligado"
        case .unauthorized: return "Sem autorização para usar o Bluetooth (Definições do Sistema → Privacidade)"
        case .unsupported: return "Este Mac não tem Bluetooth LE"
        default: return "À espera do Bluetooth…"
        }
    }

    func whenReady(_ f: @escaping () -> Void) {
        if central.state == .poweredOn { f() } else { waiters.append(f) }
    }

    func register(_ link: IqosLink) { links[link.id] = link }
    func unregister(_ link: IqosLink) { links[link.id] = nil }

    private var scanToken = 0
    var isScanning: Bool { onFound != nil }

    /// Começa uma procura e devolve o seu número; uma procura nova substitui a anterior.
    @discardableResult
    func startScan(_ found: @escaping (FoundDevice) -> Void) -> Int {
        scanToken += 1
        onFound = found
        whenReady { [weak self] in
            self?.central.scanForPeripherals(withServices: nil,
                                             options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        }
        return scanToken
    }

    /// Pára a procura (só a indicada, se vier um número).
    func stopScan(_ token: Int? = nil) {
        if let token, token != scanToken { return }
        onFound = nil
        if central.state == .poweredOn { central.stopScan() }
    }

    /// IQOS que o Mac já tem ligados por Bluetooth (por exemplo, emparelhados antes).
    func connectedIqos() -> [FoundDevice] {
        guard central.state == .poweredOn else { return [] }
        return central.retrieveConnectedPeripherals(withServices: [CBUUID(string: IqosUUID.coreService)]).map {
            FoundDevice(id: $0.identifier.uuidString, name: $0.name ?? "IQOS", rssi: 0)
        }
    }

    // MARK: CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            let w = waiters
            waiters.removeAll()
            w.forEach { $0() }
        } else {
            for l in links.values { l.bluetoothUnavailable(stateText ?? "") }
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name
        let uuids = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?.map(\.uuidString)
        guard looksLikeIqos(name: name, serviceUUIDs: uuids) else { return }
        onFound?(FoundDevice(id: peripheral.identifier.uuidString, name: name ?? "IQOS", rssi: RSSI.intValue))
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        links[peripheral.identifier]?.didConnect()
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        links[peripheral.identifier]?.didDisconnect(error)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        links[peripheral.identifier]?.didDisconnect(error)
    }
}

/// Mantém um IQOS ligado: reconecta sozinho e lê a telemetria periodicamente.
final class IqosLink: NSObject, DeviceLink, CBPeripheralDelegate {
    let id: UUID
    var pollSeconds: Double {
        didSet { if pollTimer != nil { startPolling() } }
    }

    private let cb: LinkCallbacks
    private var running = false
    private var peripheral: CBPeripheral?
    private var batteryChar: CBCharacteristic?
    private var scpChar: CBCharacteristic?
    private var servicesPending = 0
    private var ready = false
    private var delay: Double = 3
    private var reconnectWork: DispatchWorkItem?
    private var pollTimer: Timer?
    private var refreshing = false

    private struct Request {
        var command: Data
        var done: (Data?) -> Void
    }

    private var queue: [Request] = []
    private var inFlight: Request?
    private var buffer = Data()
    private var timeoutWork: DispatchWorkItem?

    init(id: UUID, pollSeconds: Double, callbacks: LinkCallbacks) {
        self.id = id
        self.pollSeconds = pollSeconds
        self.cb = callbacks
    }

    func start() {
        guard !running else { return }
        running = true
        Bluetooth.shared.register(self)
        cb.onStatus(false, "A ligar…")
        Bluetooth.shared.whenReady { [weak self] in self?.connect() }
    }

    func stop() {
        running = false
        reconnectWork?.cancel()
        teardown()
        if let p = peripheral { Bluetooth.shared.central.cancelPeripheralConnection(p) }
        Bluetooth.shared.unregister(self)
        cb.onStatus(false, "Desligado")
    }

    private func connect() {
        guard running else { return }
        cb.onStatus(false, "A ligar…")
        let central = Bluetooth.shared.central!
        guard let p = central.retrievePeripherals(withIdentifiers: [id]).first else {
            retry("IQOS não encontrado")
            return
        }
        peripheral = p
        p.delegate = self
        central.connect(p, options: nil)
    }

    private func retry(_ why: String) {
        guard running else { return }
        cb.onStatus(false, "\(why); nova tentativa…")
        reconnectWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.connect() }
        reconnectWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        delay = min(delay * 2, 60)
    }

    private func teardown() {
        pollTimer?.invalidate()
        pollTimer = nil
        ready = false
        batteryChar = nil
        scpChar = nil
        refreshing = false
        timeoutWork?.cancel()
        let pending = (inFlight.map { [$0] } ?? []) + queue
        inFlight = nil
        queue.removeAll()
        pending.forEach { $0.done(nil) }
    }

    func bluetoothUnavailable(_ text: String) {
        teardown()
        cb.onStatus(false, text)
        if running {
            Bluetooth.shared.whenReady { [weak self] in self?.connect() }
        }
    }

    func didConnect() {
        servicesPending = 0
        peripheral?.discoverServices(nil)
    }

    func didDisconnect(_ error: Error?) {
        teardown()
        if let error { log.warning("\(self.id.uuidString): \(error.localizedDescription)") }
        retry("Sem ligação")
    }

    // MARK: CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let services = peripheral.services ?? []
        servicesPending = services.count
        services.forEach { peripheral.discoverCharacteristics(nil, for: $0) }
        if services.isEmpty { didDisconnect(error) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        for c in service.characteristics ?? [] {
            switch c.uuid.uuidString.uppercased() {
            case IqosUUID.battery: batteryChar = c
            case IqosUUID.scpControl: scpChar = c
            default: break
            }
        }
        servicesPending -= 1
        guard servicesPending <= 0, !ready else { return }
        guard let battery = batteryChar else {
            Bluetooth.shared.central.cancelPeripheralConnection(peripheral)
            return
        }
        ready = true
        delay = 3
        peripheral.setNotifyValue(true, for: battery)
        if let scp = scpChar { peripheral.setNotifyValue(true, for: scp) }
        peripheral.readValue(for: battery)  // algumas versões só notificam
        cb.onStatus(true, "Ligado")
        startPolling()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.refreshTelemetry() }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard let data = characteristic.value, error == nil else { return }
        if characteristic.uuid == batteryChar?.uuid {
            if let status = parseBattery(data) {
                cb.onBattery(status)
                refreshTelemetry()  // mudança de estado: lê já a telemetria
            }
        } else if characteristic.uuid == scpChar?.uuid {
            receive(data)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error, inFlight != nil {
            log.debug("pedido falhou: \(error.localizedDescription)")
            finish(nil)
        }
    }

    // MARK: Telemetria

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: max(pollSeconds, 5), repeats: true) {
            [weak self] _ in self?.refreshTelemetry()
        }
    }

    func refreshTelemetry() {
        guard ready, scpChar != nil, !refreshing else { return }
        refreshing = true
        var t = Telemetry()
        request(IqosCommand.loadTelemetry) { [weak self] frame in
            if let frame { t = parseResponse(frame, into: t) }
            self?.request(IqosCommand.loadBatteryVoltage) { frame in
                guard let self else { return }
                if let frame { t = parseResponse(frame, into: t) }
                self.refreshing = false
                if self.ready { self.cb.onTelemetry(t) }
            }
        }
    }

    private func request(_ command: Data, done: @escaping (Data?) -> Void) {
        queue.append(Request(command: command, done: done))
        pump()
    }

    private func pump() {
        guard inFlight == nil, !queue.isEmpty else { return }
        guard let p = peripheral, let scp = scpChar else {
            let r = queue.removeFirst()
            r.done(nil)
            return
        }
        let r = queue.removeFirst()
        inFlight = r
        buffer = Data()
        p.writeValue(r.command, for: scp, type: .withResponse)
        armTimeout(3)
    }

    private func armTimeout(_ seconds: Double) {
        timeoutWork?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.finish(self.buffer.isEmpty ? nil : self.buffer)
        }
        timeoutWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: w)
    }

    private func receive(_ data: Data) {
        guard inFlight != nil else { return }
        buffer.append(data)
        // Junta fragmentos se a resposta vier partida em várias notificações.
        if let expected = telemetryExpectedLength(buffer), buffer.count < expected {
            armTimeout(0.5)
            return
        }
        finish(buffer)
    }

    private func finish(_ frame: Data?) {
        timeoutWork?.cancel()
        guard let r = inFlight else { return }
        inFlight = nil
        r.done(frame)
        pump()
    }
}
