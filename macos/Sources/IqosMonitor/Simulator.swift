// IQOS fictício para experimentar a app sem hardware (--demo).
// Mesma sequência de SimulatedConnection em iqos_monitor/ble.py.

import Foundation
import IqosCore

final class SimulatedLink: DeviceLink {
    var pollSeconds: Double
    private let cb: LinkCallbacks
    private var task: Task<Void, Never>?
    private let speed: Double

    init(pollSeconds: Double, callbacks: LinkCallbacks, speed: Double = 1) {
        self.pollSeconds = pollSeconds
        self.cb = callbacks
        self.speed = speed
    }

    func start() {
        guard task == nil else { return }
        let cb = self.cb, speed = self.speed
        task = Task { @MainActor in
            func wait(_ s: Double) async throws { try await Task.sleep(for: .seconds(s / speed)) }
            do {
                cb.onStatus(false, "A ligar…")
                try await wait(1)
                cb.onStatus(true, "Ligado (simulação)")
                var charger = Int.random(in: 60...100), holder = 100, count = Int.random(in: 500...3000)
                while true {
                    // Holder no carregador
                    cb.onBattery(BatteryStatus(charger, holder, true))
                    cb.onTelemetry(Telemetry(smokingCount: count, batteryVoltage: 3.6 + Double(charger) / 170))
                    try await wait(.random(in: 6...12))
                    // Tira o holder e fuma
                    cb.onBattery(BatteryStatus(charger, nil, false))
                    try await wait(.random(in: 5...9))
                    count += 1
                    cb.onTelemetry(Telemetry(smokingCount: count))
                    try await wait(3)
                    // Volta ao carregador e recarrega o holder
                    holder = 15
                    charger = max(charger - Int.random(in: 4...6), 0)
                    cb.onBattery(BatteryStatus(charger, holder, true))
                    holder = 100
                    if charger <= 8 {
                        while charger < 100 {
                            try await wait(1)
                            charger = min(charger + 10, 100)
                            cb.onBattery(BatteryStatus(charger, holder, true))
                        }
                    }
                }
            } catch {}  // cancelado
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        cb.onStatus(false, "Desligado")
    }
}
