// Stock de tabaco: o que o utilizador comprou, descontado a cada cigarro.
// Tradução direta de iqos_monitor/stock.py: mesmas regras e limites.
//
// É partilhado por todos os IQOS (os sticks saem todos do mesmo sítio). Avisa
// quando o maço aberto está a acabar, quando o stock fica baixo e quando acaba.

import Foundation

private func plural(_ n: Int, _ one: String, _ many: String) -> String {
    "\(n) \(n == 1 ? one : many)"
}

public struct Stock: Codable, Equatable, Sendable {
    /// nil = o utilizador ainda não disse quanto tabaco tem (não há avisos).
    public var sticksLeft: Int?
    /// Sticks por maço.
    public var packSize = 20
    /// Maços por volume.
    public var packsPerCarton = 10
    /// Avisar quando restam isto no maço aberto (0 = quando o maço acaba).
    public var packWarnSticks = 2
    /// Avisar quando restam isto em maços (10 = 1 volume; 0 = nunca).
    public var lowStockPacks = 10
    public var notify = true
    /// Data (AAAA-MM-DD) desde a qual contamos o consumo, para estimar os dias.
    public var since = ""
    /// Sticks fumados desde essa data.
    public var consumed = 0

    enum CodingKeys: String, CodingKey {
        case sticksLeft = "sticks_left", packSize = "pack_size", packsPerCarton = "packs_per_carton"
        case packWarnSticks = "pack_warn_sticks", lowStockPacks = "low_stock_packs", notify
        case since, consumed
    }

    public init(sticksLeft: Int? = nil, packSize: Int = 20, packsPerCarton: Int = 10,
                packWarnSticks: Int = 2, lowStockPacks: Int = 10, notify: Bool = true) {
        self.sticksLeft = sticksLeft
        self.packSize = packSize
        self.packsPerCarton = packsPerCarton
        self.packWarnSticks = packWarnSticks
        self.lowStockPacks = lowStockPacks
        self.notify = notify
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sticksLeft = try c.decodeIfPresent(Int.self, forKey: .sticksLeft)
        packSize = try max(c.decodeIfPresent(Int.self, forKey: .packSize) ?? 20, 1)
        packsPerCarton = try max(c.decodeIfPresent(Int.self, forKey: .packsPerCarton) ?? 10, 1)
        packWarnSticks = try c.decodeIfPresent(Int.self, forKey: .packWarnSticks) ?? 2
        lowStockPacks = try c.decodeIfPresent(Int.self, forKey: .lowStockPacks) ?? 10
        notify = try c.decodeIfPresent(Bool.self, forKey: .notify) ?? true
        since = try c.decodeIfPresent(String.self, forKey: .since) ?? ""
        consumed = try c.decodeIfPresent(Int.self, forKey: .consumed) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        // Como o Python: sticks_left vai sempre, null quando não se conta.
        try c.encode(sticksLeft, forKey: .sticksLeft)
        try c.encode(packSize, forKey: .packSize)
        try c.encode(packsPerCarton, forKey: .packsPerCarton)
        try c.encode(packWarnSticks, forKey: .packWarnSticks)
        try c.encode(lowStockPacks, forKey: .lowStockPacks)
        try c.encode(notify, forKey: .notify)
        try c.encode(since, forKey: .since)
        try c.encode(consumed, forKey: .consumed)
    }

    // MARK: Contas

    public var tracking: Bool { sticksLeft != nil }
    public var cartonSize: Int { packSize * packsPerCarton }
    public var lowStockSticks: Int { lowStockPacks * packSize }

    /// Sticks no maço aberto (o maço que está a ser fumado).
    static func openLeft(_ s: Int, _ pack: Int) -> Int { s <= 0 ? 0 : (s - 1) % pack + 1 }

    public var openPackLeft: Int { Self.openLeft(sticksLeft ?? 0, packSize) }

    /// Maços por abrir, além do que está aberto.
    public var closedPacks: Int { ((sticksLeft ?? 0) - openPackLeft) / packSize }

    /// Ex.: "2 volumes, 3 maços e 7 sticks".
    public func describe(_ sticks: Int? = nil) -> String {
        let s = sticks ?? sticksLeft ?? 0
        guard s > 0 else { return "sem tabaco" }
        let cartons = s / cartonSize, rest = s % cartonSize
        let packs = rest / packSize, loose = rest % packSize
        var parts: [String] = []
        if cartons > 0 { parts.append(plural(cartons, "volume", "volumes")) }
        if packs > 0 { parts.append(plural(packs, "maço", "maços")) }
        if loose > 0 { parts.append(plural(loose, "stick", "sticks")) }
        if parts.count == 1 { return parts[0] }
        return parts.dropLast().joined(separator: ", ") + " e " + parts.last!
    }

    /// Média de sticks por dia desde que começámos a contar.
    public func perDay(today: Date) -> Double? {
        guard consumed > 0, let start = Self.parseDay(since) else { return nil }
        let cal = Calendar.current
        let days = (cal.dateComponents([.day], from: cal.startOfDay(for: start),
                                       to: cal.startOfDay(for: today)).day ?? 0) + 1
        return Double(consumed) / Double(max(days, 1))
    }

    public func daysLeft(today: Date) -> Int? {
        guard let left = sticksLeft, let avg = perDay(today: today), avg > 0 else { return nil }
        return Int(Double(left) / avg)
    }

    static func parseDay(_ s: String) -> Date? {
        let p = s.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return DateComponents(calendar: .current, year: p[0], month: p[1], day: p[2]).date
    }

    // MARK: Ações do utilizador

    /// Comprei tabaco.
    public mutating func add(cartons: Int = 0, packs: Int = 0, sticks: Int = 0, now: Date = Date()) {
        let n = cartons * cartonSize + packs * packSize + sticks
        guard n > 0 else { return }
        start(now)
        sticksLeft = (sticksLeft ?? 0) + n
    }

    /// Corrigir: tenho exatamente isto.
    public mutating func set(_ sticks: Int, now: Date = Date()) {
        start(now)
        sticksLeft = max(sticks, 0)
    }

    /// Deixar de contar o stock.
    public mutating func stop() {
        sticksLeft = nil
        since = ""
        consumed = 0
    }

    mutating func start(_ now: Date) {
        if since.isEmpty {
            since = DeviceState.dayString(now)
            consumed = 0
        }
    }

    // MARK: Consumo

    /// Desconta n sticks fumados e devolve os avisos que isso provoca.
    public mutating func consume(_ n: Int) -> [Alert] {
        guard let before = sticksLeft, n > 0 else { return [] }
        let after = max(before - n, 0)
        sticksLeft = after
        consumed += min(n, before)
        guard notify, before > 0 else { return [] }

        if after == 0 {
            return [Alert(kind: .stockEmpty, title: "Acabou o tabaco",
                          message: "Fumou o último stick. Registe a próxima compra para voltar a contar.")]
        }

        var alerts: [Alert] = []
        let low = lowStockSticks
        if before > low && low >= after {
            alerts.append(Alert(kind: .stockLow, title: "Está a acabar o tabaco",
                                message: "Resta \(describe(after)). Está na altura de comprar."))
        }

        let pack = packSize
        let openBefore = Self.openLeft(before, pack)
        let openAfter = Self.openLeft(after, pack)
        let newPack = (before - 1) / pack != (after - 1) / pack
        let warn = packWarnSticks
        if warn > 0 && openAfter <= warn && (openBefore > warn || newPack) {
            let left = (after - openAfter) / pack
            let then = left > 0 ? "Depois disso tem \(plural(left, "maço", "maços"))." : "É o último maço."
            alerts.append(Alert(kind: .packLow, title: "O maço está a acabar",
                                message: "Restam \(plural(openAfter, "stick", "sticks")) neste maço. \(then)"))
        } else if warn <= 0 && after % pack == 0 && newPack {
            alerts.append(Alert(kind: .packLow, title: "Maço acabado",
                                message: "Abra um maço novo. Resta \(describe(after))."))
        }
        return alerts
    }
}
