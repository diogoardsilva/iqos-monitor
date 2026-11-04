// Contagem e alertas, independente do Bluetooth (testável).
// Tradução direta de iqos_monitor/tracker.py: mesmas regras e limites.

import Foundation

/// Subida da bateria do carregador a partir da qual consideramos que está a carregar.
public let chargingRisePct = 5
/// Sem telemetria: queda do holder (fora/dentro do carregador) que conta como um stick.
public let holderDropPerStickPct = 25
/// Abaixo disto o holder ainda não chega para um cigarro inteiro.
public let holderReadyPct = 95
/// Proteção contra leituras estranhas do contador do dispositivo.
public let maxSticksPerUpdate = 5

public struct Alert: Equatable, Sendable {
    public enum Kind: String, Sendable {
        // Avisam com notificação:
        case stickEnd = "stick_end", holderCharge = "holder_charge"
        case lowBattery = "low_battery", charged
        // Stock de tabaco (Stock.swift):
        case packLow = "pack_low", stockLow = "stock_low", stockEmpty = "stock_empty"
        // Só abrem a janela do canto:
        case holderOut = "holder_out", holderIn = "holder_in"
    }

    public var kind: Kind
    public var title: String
    public var message: String

    public init(kind: Kind, title: String, message: String) {
        self.kind = kind
        self.title = title
        self.message = message
    }
}

public struct DeviceState: Identifiable, Codable, Equatable, Sendable {
    // Persistente
    public var address: String
    public var name: String
    public var alias: String
    public var pctPerStick: Double
    public var smokingCount: Int?
    public var sticksToday = 0
    public var today = ""
    public var sticksSinceCharge = 0
    public var totalSticksSeen = 0
    // Volátil
    public var connected = false
    public var statusText = "Desligado"
    public var chargerPct: Int?
    public var holderPct: Int?
    public var holderInCharger: Bool?
    public var telemetryOK = false
    public var batteryVoltage: Double?
    public var lastEvent = ""
    public var holderSticksSinceCharge = 0
    var anchorPct: Int?  // bateria do carregador no último stick
    var minPctSinceCharge: Int?
    public private(set) var charging = false
    var lowAlerted = false
    var holderBeforeRemoval: Int?

    public var id: String { address }

    enum CodingKeys: String, CodingKey {
        case address, name, alias
        case pctPerStick = "pct_per_stick", smokingCount = "smoking_count"
        case sticksToday = "sticks_today", today
        case sticksSinceCharge = "sticks_since_charge", totalSticksSeen = "total_sticks_seen"
    }

    public init(address: String, name: String, alias: String = "", pctPerStick: Double = 0,
                sticksToday: Int = 0) {
        self.address = address
        self.name = name
        self.alias = alias.isEmpty ? name : alias
        self.pctPerStick = pctPerStick
        self.sticksToday = sticksToday
        if self.pctPerStick <= 0 {
            self.pctPerStick = 100.0 / Double(Model.from(name: name).sticksPerFullCharge)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(address: try c.decode(String.self, forKey: .address),
                  name: try c.decodeIfPresent(String.self, forKey: .name) ?? "IQOS",
                  alias: try c.decodeIfPresent(String.self, forKey: .alias) ?? "",
                  pctPerStick: try c.decodeIfPresent(Double.self, forKey: .pctPerStick) ?? 0,
                  sticksToday: try c.decodeIfPresent(Int.self, forKey: .sticksToday) ?? 0)
        smokingCount = try c.decodeIfPresent(Int.self, forKey: .smokingCount)
        today = try c.decodeIfPresent(String.self, forKey: .today) ?? ""
        sticksSinceCharge = try c.decodeIfPresent(Int.self, forKey: .sticksSinceCharge) ?? 0
        totalSticksSeen = try c.decodeIfPresent(Int.self, forKey: .totalSticksSeen) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(address, forKey: .address)
        try c.encode(name, forKey: .name)
        try c.encode(alias, forKey: .alias)
        try c.encode(pctPerStick, forKey: .pctPerStick)
        try c.encodeIfPresent(smokingCount, forKey: .smokingCount)
        try c.encode(sticksToday, forKey: .sticksToday)
        try c.encode(today, forKey: .today)
        try c.encode(sticksSinceCharge, forKey: .sticksSinceCharge)
        try c.encode(totalSticksSeen, forKey: .totalSticksSeen)
    }

    public var model: Model { Model.from(name: name) }

    /// O holder tem carga para um cigarro (só sabemos ao sair do carregador).
    public var holderReady: Bool { (holderPct ?? 0) >= holderReadyPct && holderPct != nil }

    // MARK: Estimativas

    /// Sticks que ainda se podem fumar com a carga atual (estimativa).
    public var sticksRemaining: Int? {
        guard let charger = chargerPct else { return nil }
        let fromCharger = Int(Double(charger) / max(pctPerStick, 0.5))
        if model.onePiece { return fromCharger }
        // Holder: o que ainda tem agora + recargas que o carregador consegue dar.
        var holderLeft = max(model.sticksPerHolderCharge - holderSticksSinceCharge, 0)
        if holderInCharger == true, let h = holderPct, h < 100 {
            holderLeft = 0  // ainda está a recarregar; a recarga sai do carregador
        }
        return fromCharger + holderLeft
    }

    // MARK: Eventos

    static func dayString(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func hhmm(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    mutating func rollDay(_ now: Date) {
        let day = Self.dayString(now)
        if today != day {
            today = day
            sticksToday = 0
        }
    }

    public mutating func onBattery(_ b: BatteryStatus, now: Date, lowPct: Int) -> [Alert] {
        rollDay(now)
        var alerts: [Alert] = []
        let prevPct = chargerPct
        let prevIn = holderInCharger

        chargerPct = b.chargerPct
        holderInCharger = b.holderInCharger
        if let h = b.holderPct { holderPct = h }

        // Holder entrou no carregador: recarrega, volta a ter sticks disponíveis.
        if b.holderInCharger && prevIn == false {
            if !telemetryOK, let before = holderBeforeRemoval, let h = b.holderPct,
               before - h >= holderDropPerStickPct {
                alerts += registerSticks(1, now: now)
            }
            holderSticksSinceCharge = 0
            alerts.append(Alert(kind: .holderIn, title: "Holder no carregador", message: alias))
        }
        if !b.holderInCharger && prevIn == true {
            holderBeforeRemoval = holderPct
            alerts.append(Alert(kind: .holderOut, title: "Holder fora do carregador", message: alias))
        }

        // Deteção de carregamento do carregador / dispositivo.
        if minPctSinceCharge == nil || b.chargerPct < minPctSinceCharge! {
            minPctSinceCharge = b.chargerPct
        }
        if b.chargerPct - (minPctSinceCharge ?? b.chargerPct) >= chargingRisePct && !charging {
            charging = true
            lowAlerted = false
            sticksSinceCharge = 0
            anchorPct = nil
            lastEvent = "A carregar (\(b.chargerPct)%)"
        }
        if charging && b.chargerPct >= 100 && (prevPct ?? 0) < 100 {
            alerts.append(Alert(kind: .charged, title: "Carga completa",
                                message: "\(alias) está com 100%. Pode tirar do carregador."))
        }
        if charging, let prev = prevPct, b.chargerPct < prev {
            // Deixou de carregar (começou a descer outra vez).
            charging = false
            minPctSinceCharge = b.chargerPct
        }

        alerts += checkLow(lowPct)
        return alerts
    }

    public mutating func onTelemetry(_ t: Telemetry, now: Date, lowPct: Int) -> [Alert] {
        rollDay(now)
        if let v = t.batteryVoltage { batteryVoltage = v }
        guard let count = t.smokingCount else { return [] }
        telemetryOK = true
        var alerts: [Alert] = []
        if let prev = smokingCount, count > prev {
            let n = count - prev
            if n <= maxSticksPerUpdate {
                alerts += registerSticks(n, now: now)
            }
        }
        smokingCount = count
        alerts += checkLow(lowPct)
        return alerts
    }

    mutating func registerSticks(_ n: Int, now: Date) -> [Alert] {
        sticksToday += n
        sticksSinceCharge += n
        totalSticksSeen += n
        holderSticksSinceCharge += n
        learn(n)
        let remTxt = sticksRemaining.map { " Restam ~\($0)." } ?? ""
        lastEvent = "Cigarro terminado às \(Self.hhmm(now))"
        var alerts = [Alert(kind: .stickEnd, title: "Cigarro terminado",
                            message: "\(alias): \(sticksToday) hoje, "
                                + "\(sticksSinceCharge) desde a última carga.\(remTxt)")]
        if !model.onePiece && holderSticksSinceCharge >= model.sticksPerHolderCharge
            && holderInCharger != true {
            alerts.append(Alert(kind: .holderCharge, title: "Ponha o holder a carregar",
                                message: "\(alias): o holder precisa de voltar ao carregador "
                                    + "antes do próximo cigarro."))
        }
        return alerts
    }

    /// Aprende quantos % do carregador gasta cada stick (média móvel).
    mutating func learn(_ n: Int) {
        guard let charger = chargerPct else { return }
        if let anchor = anchorPct, !charging {
            let drop = Double(anchor - charger) / Double(n)
            if drop > 0 && drop <= 30 {
                pctPerStick = ((0.8 * pctPerStick + 0.2 * drop) * 100).rounded() / 100
            }
        }
        anchorPct = charger
    }

    mutating func checkLow(_ lowPct: Int) -> [Alert] {
        guard let charger = chargerPct, !charging, !lowAlerted else { return [] }
        let rem = sticksRemaining
        if charger <= lowPct || (rem.map { $0 <= 1 } ?? false) {
            lowAlerted = true
            let what = model.onePiece ? "o IQOS" : "o carregador"
            let remTxt = rem.map(String.init) ?? "None"
            return [Alert(kind: .lowBattery, title: "Bateria fraca",
                          message: "\(alias): \(charger)% (~\(remTxt) cigarros). Ponha \(what) a carregar.")]
        }
        return []
    }
}

public struct Settings: Codable, Equatable, Sendable {
    public var lowBatteryPct = 20
    public var pollSeconds = 20
    public var notifyStickEnd = true
    public var autoUpdate = true
    public var showPopup = true
    public var devices: [DeviceState] = []
    public var stock = Stock()

    enum CodingKeys: String, CodingKey {
        case lowBatteryPct = "low_battery_pct", pollSeconds = "poll_seconds"
        case notifyStickEnd = "notify_stick_end", autoUpdate = "auto_update"
        case showPopup = "show_popup", devices, stock
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lowBatteryPct = try c.decodeIfPresent(Int.self, forKey: .lowBatteryPct) ?? 20
        pollSeconds = try c.decodeIfPresent(Int.self, forKey: .pollSeconds) ?? 20
        notifyStickEnd = try c.decodeIfPresent(Bool.self, forKey: .notifyStickEnd) ?? true
        autoUpdate = try c.decodeIfPresent(Bool.self, forKey: .autoUpdate) ?? true
        showPopup = try c.decodeIfPresent(Bool.self, forKey: .showPopup) ?? true
        devices = try c.decodeIfPresent([DeviceState].self, forKey: .devices) ?? []
        stock = try c.decodeIfPresent(Stock.self, forKey: .stock) ?? Stock()
    }
}

/// Guarda dispositivos e preferências em ~/Library/Application Support/IqosMonitor/state.json.
public enum Storage {
    public static func directory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory())
        return base.appendingPathComponent("IqosMonitor", isDirectory: true)
    }

    public static func load(_ url: URL) -> Settings {
        guard let data = try? Data(contentsOf: url),
              let s = try? JSONDecoder().decode(Settings.self, from: data) else { return Settings() }
        return s
    }

    public static func save(_ s: Settings, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(s).write(to: url, options: .atomic)
    }
}
