// Protocolo BLE do IQOS (engenharia inversa, não oficial).
// Tradução direta de iqos_monitor/protocol.py; as fontes estão lá e no README.

import Foundation

public enum IqosUUID {
    public static let coreService = "DAEBB240-B041-11E4-9E45-0002A5D5C51B"
    public static let battery = "F8A54120-B041-11E4-9BE7-0002A5D5C51B"
    public static let scpControl = "E16C6E20-B041-11E4-A4C3-0002A5D5C51B"
    public static let deviceStatus = "ECDFA4C0-B041-11E4-8B67-0002A5D5C51B"
}

public enum IqosCommand {
    /// Pedido de telemetria (contador total de utilizações / dias de uso).
    public static let loadTelemetry = Data([0x00, 0xC9, 0x10, 0x02, 0x01, 0x01, 0x75, 0xD6])
    /// Pedido de voltagem da bateria.
    public static let loadBatteryVoltage = Data([0x00, 0xC0, 0x00, 0x21, 0xE7])
}

let telemetryHeader: (UInt8, UInt8) = (0x90, 0x22)
let timestampHeader: (UInt8, UInt8) = (0x80, 0x02)
let batteryVoltageHeader: (UInt8, UInt8) = (0x88, 0x21)
let tagSmokingCount: UInt8 = 0x8E
let tagDayCounter: UInt8 = 0x17
let telemetryBlockSize = 8

public enum Model: String, CaseIterable, Sendable {
    case ilumaOne = "ILUMA ONE"
    case iluma = "ILUMA"
    case ilumaPrime = "ILUMA PRIME"
    case ilumaIOne = "ILUMA i ONE"
    case ilumaI = "ILUMA i"
    case ilumaIPrime = "ILUMA i PRIME"
    case iqos3 = "IQOS 3 / DUO"
    case unknown = "IQOS"

    public static func from(name: String?) -> Model {
        let n = (name ?? "").trimmingCharacters(in: .whitespaces).uppercased()
        if n.contains("ILUMA I PRIME") { return .ilumaIPrime }
        if n.contains("ILUMA I ONE") { return .ilumaIOne }
        if n.contains("ILUMA I") { return .ilumaI }
        if n.contains("ILUMA PRIME") { return .ilumaPrime }
        if n.contains("ILUMA ONE") { return .ilumaOne }
        if n.contains("ILUMA") { return .iluma }
        if n.contains("IQOS") { return .iqos3 }
        return .unknown
    }

    /// Modelos de uma só peça (sem holder separado do carregador).
    public var onePiece: Bool { self == .ilumaOne || self == .ilumaIOne }

    /// Estimativa inicial de sticks por carga completa; a app aprende o consumo real.
    public var sticksPerFullCharge: Int { 20 }

    /// Quantos sticks seguidos o holder aguenta antes de voltar ao carregador.
    public var sticksPerHolderCharge: Int {
        if onePiece { return sticksPerFullCharge }
        if self == .ilumaI || self == .ilumaIPrime { return 2 }
        return 1
    }
}

public func looksLikeIqos(name: String?, serviceUUIDs: [String]? = nil) -> Bool {
    if let uuids = serviceUUIDs, uuids.contains(where: { $0.uppercased() == IqosUUID.coreService }) {
        return true
    }
    return (name ?? "").uppercased().contains("IQOS")
}

/// Leitura da característica de bateria. O holder só se conhece quando está no carregador.
public struct BatteryStatus: Equatable, Sendable {
    public var chargerPct: Int
    public var holderPct: Int?
    public var holderInCharger: Bool

    public init(_ chargerPct: Int, _ holderPct: Int?, _ holderInCharger: Bool) {
        self.chargerPct = chargerPct
        self.holderPct = holderPct
        self.holderInCharger = holderInCharger
    }
}

public func parseBattery(_ frame: Data) -> BatteryStatus? {
    let b = [UInt8](frame)
    guard b.count >= 3 else { return nil }
    let charger = min(Int(b[2]), 100)
    if b.count >= 7 {
        return BatteryStatus(charger, min(Int(b[6]), 100), true)
    }
    return BatteryStatus(charger, nil, false)
}

public struct Telemetry: Equatable, Sendable {
    public var smokingCount: Int?
    public var daysUsed: Int?
    public var batteryVoltage: Double?

    public init(smokingCount: Int? = nil, daysUsed: Int? = nil, batteryVoltage: Double? = nil) {
        self.smokingCount = smokingCount
        self.daysUsed = daysUsed
        self.batteryVoltage = batteryVoltage
    }
}

private func le16(_ b: [UInt8], _ at: Int) -> Int {
    Int(b[at]) | (Int(b[at + 1]) << 8)
}

/// Comprimento total de uma resposta de telemetria, para juntar fragmentos.
public func telemetryExpectedLength(_ frame: Data) -> Int? {
    let b = [UInt8](frame)
    guard b.count >= 4, b[2] == telemetryHeader.0, b[3] == telemetryHeader.1 else { return nil }
    let blocks = max(Int(b[3]) - 2, 0) / telemetryBlockSize
    return 6 + blocks * telemetryBlockSize
}

/// Interpreta uma resposta SCP. Tramas desconhecidas são ignoradas.
public func parseResponse(_ frame: Data, into: Telemetry = Telemetry()) -> Telemetry {
    var t = into
    let b = [UInt8](frame)
    guard b.count >= 4 else { return t }
    let header = (b[2], b[3])
    if header == telemetryHeader {
        guard b.count >= 6, le16(b, 4) == 0x0101 else { return t }
        let expected = telemetryExpectedLength(frame) ?? 0
        guard b.count >= expected else { return t }
        var off = 6
        while off + telemetryBlockSize <= expected {
            let value = le16(b, off + 4)
            switch b[off + 7] {
            case tagSmokingCount: t.smokingCount = value
            case tagDayCounter: t.daysUsed = value
            default: break
            }
            off += telemetryBlockSize
        }
    } else if header == timestampHeader, b.count >= 6 {
        t.daysUsed = le16(b, 4)
    } else if header == batteryVoltageHeader, b.count >= 7 {
        t.batteryVoltage = Double(le16(b, 5)) / 1000.0
    }
    return t
}
