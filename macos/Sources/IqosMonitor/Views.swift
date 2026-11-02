// Janela principal: cartões de vidro com anéis de bateria, como o widget Baterias.

import IqosCore
import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel
    @State private var scanning = false
    @State private var renaming: DeviceState?
    @State private var removing: DeviceState?
    @State private var newName = ""

    private var ambient: [Color] {
        let tints = model.settings.devices.map { Finish.of($0.model).accent }
        return (tints + [.teal, .indigo, .mint, .blue]).prefix(4).map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if model.settings.devices.isEmpty {
                    EmptyState { add() }
                } else {
                    GlassGroup(spacing: 18) {
                        VStack(spacing: 16) {
                            ForEach(model.settings.devices) { d in
                                DeviceCard(device: d, linked: model.linked.contains(d.id),
                                           onToggle: { model.toggleConnection(d.id) },
                                           onRename: { newName = d.alias; renaming = d },
                                           onReset: { model.resetCounts(d.id) },
                                           onRemove: { removing = d })
                                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 34)
            .padding(.bottom, 24)
            .animation(.spring(response: 0.45, dampingFraction: 0.82), value: model.settings.devices.map(\.id))
        }
        .scrollContentBackground(.hidden)
        .background(AmbientBackground(colors: ambient))
        .frame(minWidth: 380, idealWidth: 430, minHeight: 460, idealHeight: 760)
        .sheet(isPresented: $scanning) {
            ScanSheet { found in model.add(found) }
        }
        .alert("Mudar o nome", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Nome", text: $newName)
            Button("Guardar") { if let d = renaming { model.rename(d.id, to: newName) } }
            Button("Cancelar", role: .cancel) {}
        }
        .confirmationDialog("Remover \(removing?.alias ?? "")?",
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Remover", role: .destructive) { if let d = removing { model.remove(d.id) } }
        } message: {
            Text("A contagem guardada deste IQOS é apagada.")
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Os meus IQOS")
                    .font(.largeTitle.weight(.bold))
                if model.demo {
                    Text("Simulação").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(action: add) {
                Label("Adicionar", systemImage: "plus")
                    .padding(.horizontal, 4)
            }
            .glassButton(prominent: true)
            .controlSize(.large)
            .keyboardShortcut("n")

            Menu {
                SettingsLink { Text("Definições…") }
                Button("Procurar atualizações") { model.checkUpdates(manual: true) }
                if let rel = model.updateAvailable {
                    Button("Descarregar a versão \(rel.version)") { NSWorkspace.shared.open(rel.pageURL) }
                }
                Divider()
                Button("Sair") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 20, height: 20)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .glassButton()
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .fixedSize()
            .accessibilityLabel("Mais opções")
        }
    }

    private func add() {
        if model.demo { model.addSimulated() } else { scanning = true }
    }
}

struct EmptyState: View {
    var add: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
                .symbolEffect(.pulse)
            Text("Nenhum IQOS ainda").font(.title2.weight(.semibold))
            Text("Ligue o Bluetooth, ponha o IQOS em modo de emparelhamento e carregue em Adicionar.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Adicionar IQOS", action: add)
                .glassButton(prominent: true)
                .controlSize(.large)
                .padding(.top, 4)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .glassPanel()
        .padding(.top, 40)
    }
}

struct DeviceCard: View {
    var device: DeviceState
    var linked: Bool
    var onToggle: () -> Void
    var onRename: () -> Void
    var onReset: () -> Void
    var onRemove: () -> Void

    var body: some View {
        let d = device
        let one = d.model.onePiece
        VStack(spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                DeviceThumbnail(model: d.model, height: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.alias).font(.title3.weight(.semibold)).lineLimit(1)
                    HStack(spacing: 5) {
                        Circle()
                            .fill(d.connected ? Color.green : Color.secondary.opacity(0.5))
                            .frame(width: 7, height: 7)
                        Text("\(d.model.rawValue) · \(d.statusText)")
                            .lineLimit(1)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Menu {
                    Button(linked ? "Desligar" : "Ligar", action: onToggle)
                    Button("Mudar o nome…", action: onRename)
                    Button("Repor contagem", action: onReset)
                    Divider()
                    Button("Remover…", role: .destructive, action: onRemove)
                } label: {
                    Image(systemName: "ellipsis").frame(width: 16, height: 16)
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .glassButton()
                .buttonBorderShape(.circle)
                .fixedSize()
                .accessibilityLabel("Mais ações para \(d.alias)")
            }

            HStack(spacing: 28) {
                BatteryRing(caption: one ? "Bateria" : "Carregador", pct: d.chargerPct,
                            charging: d.charging, note: d.charging ? "a carregar" : "")
                if !one {
                    if d.holderInCharger == true {
                        BatteryRing(caption: "Holder", pct: d.holderPct,
                                    charging: (d.holderPct ?? 100) < 100, note: "no carregador")
                    } else {
                        BatteryRing(caption: "Holder", pct: nil,
                                    note: d.holderInCharger == false ? "fora do carregador" : "")
                    }
                }
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 0) {
                Stat(value: d.sticksRemaining.map { "~\($0)" } ?? "—", caption: "restam")
                Divider().frame(height: 30)
                Stat(value: "\(d.sticksSinceCharge)", caption: "desde a carga")
                Divider().frame(height: 30)
                Stat(value: "\(d.sticksToday)", caption: "hoje")
            }
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            let extra = [d.lastEvent, d.connected && !d.telemetryOK ? "a contar pelo holder" : ""]
                .filter { !$0.isEmpty }
            if !extra.isEmpty {
                Text(extra.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(18)
        .glassPanel(tint: Finish.of(d.model).accent)
        .contextMenu {
            Button(linked ? "Desligar" : "Ligar", action: onToggle)
            Button("Mudar o nome…", action: onRename)
            Button("Repor contagem", action: onReset)
            Divider()
            Button("Remover…", role: .destructive, action: onRemove)
        }
        .help(String(format: "%.1f%% de bateria por cigarro", d.pctPerStick)
              + (d.batteryVoltage.map { String(format: " · %.2f V", $0) } ?? ""))
    }
}

struct Stat: View {
    var value: String
    var caption: String

    var body: some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 24, weight: .semibold, design: .rounded).monospacedDigit())
                .contentTransition(.numericText())
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(caption): \(value)")
    }
}

/// Anel de capacidade com a percentagem ao centro, no estilo dos anéis de Atividade.
struct BatteryRing: View {
    var caption: String
    var pct: Int?
    var charging = false
    var note = ""
    var size: CGFloat = 92

    var body: some View {
        let color = batteryColor(pct)
        let frac = Double(pct ?? 0) / 100
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(color.opacity(pct == nil ? 0.15 : 0.18), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: frac)
                    .stroke(AngularGradient(colors: [color.opacity(0.75), color], center: .center,
                                            startAngle: .degrees(0), endAngle: .degrees(360 * max(frac, 0.01))),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: color.opacity(0.45), radius: 6)
                    .animation(.spring(response: 0.7, dampingFraction: 0.85), value: frac)
                HStack(spacing: 1) {
                    if charging && pct != nil {
                        Image(systemName: "bolt.fill").font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.green)
                            .symbolEffect(.pulse)
                    }
                    Text(pct.map { "\($0)%" } ?? "—")
                        .font(.system(size: pct == nil ? 18 : 21, weight: .semibold, design: .rounded)
                            .monospacedDigit())
                        .foregroundStyle(pct == nil ? Color.secondary : Color.primary)
                        .contentTransition(.numericText())
                }
            }
            .frame(width: size, height: size)
            VStack(spacing: 0) {
                Text(caption).font(.callout.weight(.semibold))
                Text(note.isEmpty ? " " : note).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(caption): \(pct.map { "\($0) por cento" } ?? "sem leitura")"
                            + (note.isEmpty ? "" : ", \(note)"))
    }
}

struct ScanSheet: View {
    var onAdd: ([FoundDevice]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var found: [FoundDevice] = []
    @State private var selected: Set<String> = []
    @State private var searching = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Adicionar IQOS").font(.title2.weight(.semibold))
            Text(info).foregroundStyle(.secondary)
            List(found, selection: $selected) { f in
                HStack {
                    Image(systemName: "dot.radiowaves.left.and.right")
                    Text(f.name)
                    Spacer()
                    Text("\(f.rssi) dBm").foregroundStyle(.secondary).font(.caption.monospacedDigit())
                }
                .tag(f.id)
            }
            .frame(minHeight: 160)
            .scrollContentBackground(.hidden)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            HStack {
                Button(searching ? "A procurar…" : "Procurar outra vez") { scan() }
                    .disabled(searching)
                    .glassButton()
                Spacer()
                Button("Cancelar") { dismiss() }
                    .glassButton()
                    .keyboardShortcut(.cancelAction)
                Button("Adicionar") {
                    onAdd(found.filter { selected.contains($0.id) })
                    dismiss()
                }
                .glassButton(prominent: true)
                .keyboardShortcut(.defaultAction)
                .disabled(selected.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 440, height: 360)
        .onAppear(perform: scan)
        .onDisappear { Bluetooth.shared.stopScan() }
    }

    private var info: String {
        if let state = Bluetooth.shared.stateText, Bluetooth.shared.central.state != .unknown {
            return state
        }
        if searching { return "Ponha o IQOS em modo de emparelhamento. A procurar IQOS por perto…" }
        let n = found.count
        return n == 0 ? "Não encontrei nenhum IQOS. Confirme que está em modo de emparelhamento e perto do Mac."
            : "\(n) IQOS encontrado\(n == 1 ? "" : "s")."
    }

    private func scan() {
        searching = true
        Bluetooth.shared.startScan { f in
            guard !found.contains(where: { $0.id == f.id }) else { return }
            found.append(f)
            found.sort { $0.rssi > $1.rssi }
            selected.insert(f.id)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            Bluetooth.shared.stopScan()
            searching = false
        }
    }
}

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Stepper("Avisar bateria fraca abaixo de \(model.settings.lowBatteryPct) %",
                    value: $model.settings.lowBatteryPct, in: 5...60)
            Stepper("Ler o contador a cada \(model.settings.pollSeconds) s",
                    value: $model.settings.pollSeconds, in: 5...300, step: 5)
            Toggle("Avisar quando cada cigarro termina", isOn: $model.settings.notifyStickEnd)
            Toggle("Mostrar janela no canto ao tirar o holder", isOn: $model.settings.showPopup)
            Toggle("Avisar quando houver versão nova", isOn: $model.settings.autoUpdate)
            LabeledContent("Versão", value: Updates.currentVersion)
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: model.settings.pollSeconds) { model.applySettings() }
        .onChange(of: model.settings.lowBatteryPct) { model.scheduleSave() }
        .onChange(of: model.settings.notifyStickEnd) { model.scheduleSave() }
        .onChange(of: model.settings.showPopup) { model.scheduleSave() }
        .onChange(of: model.settings.autoUpdate) { model.scheduleSave() }
    }
}

/// Painel do ícone na barra de menus.
struct MenuBarPanel: View {
    var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.settings.devices.isEmpty {
                Text("Nenhum IQOS").foregroundStyle(.secondary)
            }
            ForEach(model.settings.devices) { d in
                HStack(spacing: 10) {
                    DeviceThumbnail(model: d.model, height: 34)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(d.alias).font(.headline)
                        BatteryRow(label: d.model.onePiece ? "Bateria" : "Carregador", pct: d.chargerPct)
                        Text(d.sticksRemaining.map { "~\($0) cigarros · \(d.sticksToday) hoje" } ?? d.statusText)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassPanel(cornerRadius: 18, tint: Finish.of(d.model).accent)
            }
            HStack {
                Button("Abrir IQOS Monitor") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .glassButton(prominent: true)
                Spacer()
                Button("Sair") { NSApp.terminate(nil) }.glassButton()
            }
            .padding(.top, 2)
        }
        .padding(14)
        .frame(width: 320)
    }
}
