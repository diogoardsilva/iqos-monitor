// Conteúdo do painel da barra de menus (ver StatusPanel.swift). É a app toda:
// abre-se ao clicar no ícone, por cima de tudo, no vidro do sistema.
//
// Desenho: um módulo por IQOS, com anéis como os do widget Baterias e o
// aparelho desenhado dentro de cada anel. Os comandos da app ficam em baixo,
// em linhas de menu, como nos outros itens da barra de menus.

import IqosCore
import ServiceManagement
import SwiftUI

struct MenuPanel: View {
    @Bindable var model: AppModel
    @State private var scanning = false
    @State private var renaming: String?
    @State private var removing: String?
    var openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if scanning {
                ScanView(known: Set(model.settings.devices.map(\.id))) { found in
                    model.add(found)
                    scanning = false
                } onCancel: {
                    scanning = false
                }
            } else if model.settings.devices.isEmpty {
                empty
            } else {
                ForEach(model.settings.devices) { d in
                    DeviceModule(model: model, device: d, renaming: $renaming, removing: $removing)
                }
            }
            if !scanning && (!model.settings.devices.isEmpty || model.settings.stock.tracking) {
                StockModule(model: model)
            }
            Divider().padding(.horizontal, 4)
            footer
        }
        .padding(12)
        .frame(width: 340)
    }

    private var header: some View {
        HStack {
            Text("IQOS")
                .font(.headline)
            if model.demo {
                Text("Simulação").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if !scanning {
                Button(action: add) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 18, height: 18)
                }
                .glassControl()
                .help("Adicionar IQOS")
                .accessibilityLabel("Adicionar IQOS")
            }
        }
        .padding(.horizontal, 4)
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)
            Text("Nenhum IQOS").font(.headline)
            Text("Ponha o IQOS em modo de emparelhamento e adicione-o.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Adicionar IQOS…", action: add)
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 12)
        .background(ModuleBackground())
    }

    private var footer: some View {
        VStack(spacing: 0) {
            if let rel = model.updateAvailable {
                Button {
                    model.installUpdate(rel)
                } label: {
                    HStack {
                        Text(model.updating ? "A atualizar para a versão \(rel.version)…"
                             : "Atualizar para a versão \(rel.version)")
                        Spacer()
                        if model.updating { ProgressView().controlSize(.small) }
                    }
                }
                .buttonStyle(MenuRowStyle())
                .disabled(model.updating)
            }
            Button {
                openSettings()
            } label: {
                HStack {
                    Text("Definições…")
                    Spacer()
                    Text("⌘,").foregroundStyle(.secondary)
                }
            }
            .buttonStyle(MenuRowStyle())
            .keyboardShortcut(",")
            Button {
                NSApp.terminate(nil)
            } label: {
                HStack {
                    Text("Sair do IQOS Monitor")
                    Spacer()
                    Text("⌘Q").foregroundStyle(.secondary)
                }
            }
            .buttonStyle(MenuRowStyle())
            .keyboardShortcut("q")
        }
    }

    private func add() {
        if model.demo { model.addSimulated() } else { scanning = true }
    }
}

/// Um IQOS: nome e estado, anéis de bateria e a contagem.
struct DeviceModule: View {
    var model: AppModel
    var device: DeviceState
    @Binding var renaming: String?
    @Binding var removing: String?
    @State private var newName = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        let d = device
        let one = d.model.onePiece
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    if renaming == d.id {
                        TextField("Nome", text: $newName)
                            .textFieldStyle(.roundedBorder)
                            .focused($nameFocused)
                            .onSubmit { model.rename(d.id, to: newName); renaming = nil }
                            .onExitCommand { renaming = nil }
                            .onAppear { newName = d.alias; nameFocused = true }
                    } else {
                        Text(d.alias).font(.headline).lineLimit(1)
                    }
                    Text(statusLine(d))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                actionsMenu(d)
            }

            HStack(alignment: .top, spacing: 22) {
                BatteryRing(kind: one ? .one : .charger, model: d.model,
                            caption: one ? "IQOS" : "Carregador", pct: d.chargerPct, charging: d.charging)
                if !one {
                    BatteryRing(kind: .holder, model: d.model, caption: "Holder",
                                pct: d.holderInCharger == true ? d.holderPct : nil,
                                charging: d.holderInCharger == true && (d.holderPct ?? 100) < 100,
                                note: d.holderInCharger == false ? "fora" : nil)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 6) {
                    Count(value: d.sticksRemaining.map { "~\($0)" } ?? "—", caption: "restam")
                    Count(value: "\(d.sticksToday)", caption: "hoje")
                }
            }

            if let extra = extraLine(d) {
                Text(extra).font(.caption).foregroundStyle(.secondary)
            }

            if removing == d.id {
                HStack {
                    Text("Remover \(d.alias)? A contagem é apagada.")
                        .font(.callout)
                    Spacer()
                    Button("Cancelar") { removing = nil }
                        .keyboardShortcut(.cancelAction)
                    Button("Remover", role: .destructive) { model.remove(d.id); removing = nil }
                }
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(ModuleBackground())
        .contextMenu { menuItems(d) }
        .help(String(format: "%.1f%% de bateria por cigarro", d.pctPerStick)
              + (d.batteryVoltage.map { String(format: " · %.2f V", $0) } ?? ""))
    }

    private func statusLine(_ d: DeviceState) -> String {
        "\(d.model.rawValue) · \(d.statusText)"
    }

    private func extraLine(_ d: DeviceState) -> String? {
        let parts = ["\(d.sticksSinceCharge) desde a última carga", d.lastEvent,
                     d.connected && !d.telemetryOK ? "a contar pelo holder" : ""]
            .filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }

    private func actionsMenu(_ d: DeviceState) -> some View {
        Menu {
            menuItems(d)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 16, height: 16)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .glassControl()
        .fixedSize()
        .accessibilityLabel("Ações para \(d.alias)")
    }

    @ViewBuilder
    private func menuItems(_ d: DeviceState) -> some View {
        Button(model.linked.contains(d.id) ? "Desligar" : "Ligar") { model.toggleConnection(d.id) }
        Button("Mudar o nome…") { removing = nil; renaming = d.id }
        Button("Repor contagem") { model.resetCounts(d.id) }
        Divider()
        Button("Remover…", role: .destructive) { renaming = nil; removing = d.id }
    }
}

struct Count: View {
    var value: String
    var caption: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(value)
                .font(.title2.weight(.semibold).monospacedDigit())
                .contentTransition(.numericText())
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(caption): \(value)")
    }
}

/// Anel como os do widget Baterias: o aparelho ao centro e a percentagem por baixo.
struct BatteryRing: View {
    var kind: ArtKind
    var model: Model
    var caption: String
    var pct: Int?
    var charging = false
    var note: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let color = batteryColor(pct)
        let frac = Double(pct ?? 0) / 100
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.12), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: frac)
                    .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .smooth(duration: 0.6), value: frac)
                DeviceGlyph(kind: kind, model: model, height: kind == .holder ? 38 : 34)
                    .opacity(pct == nil ? 0.45 : 1)
                if charging && pct != nil {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(Color.green))
                        .offset(x: 21, y: -21)
                }
            }
            .frame(width: 58, height: 58)
            Text(pct.map { "\($0)%" } ?? (note ?? "—"))
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(pct == nil ? Color.secondary : Color.primary)
                .contentTransition(.numericText())
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(caption): \(pct.map { "\($0) por cento" } ?? (note.map { "\($0) do carregador" } ?? "sem leitura"))"
                            + (charging ? ", a carregar" : ""))
    }
}

/// Procura de IQOS, dentro do próprio painel.
struct ScanView: View {
    var known: Set<String>
    var onAdd: ([FoundDevice]) -> Void
    var onCancel: () -> Void
    @State private var found: [FoundDevice] = []
    @State private var selected: Set<String> = []
    @State private var searching = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if searching { ProgressView().controlSize(.small) }
                Text(info).font(.callout).foregroundStyle(.secondary)
            }
            if !found.isEmpty {
                VStack(spacing: 0) {
                    ForEach(found) { f in
                        Button {
                            if selected.contains(f.id) { selected.remove(f.id) } else { selected.insert(f.id) }
                        } label: {
                            HStack {
                                Image(systemName: selected.contains(f.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(f.id) ? Color.accentColor : Color.secondary)
                                Text(f.name)
                                Spacer()
                                Text("\(f.rssi) dBm").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(MenuRowStyle())
                    }
                }
            }
            HStack {
                if !searching {
                    Button("Procurar outra vez", action: scan)
                }
                Spacer()
                Button("Cancelar", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Adicionar") { onAdd(found.filter { selected.contains($0.id) }) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selected.isEmpty)
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(ModuleBackground())
        .onAppear(perform: scan)
        .onDisappear { Bluetooth.shared.stopScan() }
    }

    private var info: String {
        if let state = Bluetooth.shared.stateText, Bluetooth.shared.central.state != .unknown {
            return state
        }
        if searching { return "A procurar IQOS em modo de emparelhamento…" }
        let n = found.count
        return n == 0 ? "Nenhum IQOS por perto. Confirme que está em modo de emparelhamento."
            : "\(n) IQOS encontrado\(n == 1 ? "" : "s")."
    }

    private func scan() {
        searching = true
        Bluetooth.shared.startScan { f in
            guard !known.contains(f.id), !found.contains(where: { $0.id == f.id }) else { return }
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
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                Toggle("Abrir ao iniciar sessão", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) {
                        do {
                            if openAtLogin { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                        } catch {
                            openAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
            Section("Avisos") {
                Toggle("Quando cada cigarro termina", isOn: $model.settings.notifyStickEnd)
                Toggle("Janela no canto ao tirar o holder", isOn: $model.settings.showPopup)
                Picker("Bateria fraca abaixo de", selection: $model.settings.lowBatteryPct) {
                    ForEach(options([10, 15, 20, 25, 30, 40], model.settings.lowBatteryPct), id: \.self) { Text("\($0) %").tag($0) }
                }
            }
            Section("Tabaco") {
                Toggle("Avisar quando o tabaco estiver a acabar", isOn: $model.settings.stock.notify)
                Stepper("Cada maço tem \(model.settings.stock.packSize) sticks",
                        value: $model.settings.stock.packSize, in: 1...40)
                Stepper("Cada volume tem \(model.settings.stock.packsPerCarton) maços",
                        value: $model.settings.stock.packsPerCarton, in: 1...20)
                Picker("Avisar o maço quando restam", selection: $model.settings.stock.packWarnSticks) {
                    Text("quando acaba").tag(0)
                    ForEach(options([1, 2, 3, 4, 5], model.settings.stock.packWarnSticks).filter { $0 > 0 },
                            id: \.self) { Text("\($0) \($0 == 1 ? "stick" : "sticks")").tag($0) }
                }
                Picker("Avisar o stock quando resta", selection: $model.settings.stock.lowStockPacks) {
                    Text("nunca").tag(0)
                    ForEach(options([1, 2, 5, 10, 20], model.settings.stock.lowStockPacks).filter { $0 > 0 },
                            id: \.self) { n in
                        Text(packsLabel(n)).tag(n)
                    }
                }
            }
            Section("Ligação") {
                Picker("Ler o contador a cada", selection: $model.settings.pollSeconds) {
                    ForEach(options([10, 20, 30, 60, 120], model.settings.pollSeconds), id: \.self) { Text("\($0) s").tag($0) }
                }
                Toggle("Instalar atualizações automaticamente", isOn: $model.settings.autoUpdate)
            }
            Section {
                LabeledContent("Versão", value: Updates.currentVersion)
                Button("Procurar atualizações") { model.checkUpdates(manual: true) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: model.settings.pollSeconds) { model.applySettings() }
        .onChange(of: model.settings.lowBatteryPct) { model.scheduleSave() }
        .onChange(of: model.settings.notifyStickEnd) { model.scheduleSave() }
        .onChange(of: model.settings.showPopup) { model.scheduleSave() }
        .onChange(of: model.settings.autoUpdate) { model.scheduleSave() }
        .onChange(of: model.settings.stock) { model.scheduleSave() }
    }

    /// "1 volume" quando dá certo, senão "5 maços".
    private func packsLabel(_ n: Int) -> String {
        let per = model.settings.stock.packsPerCarton
        if per > 0 && n % per == 0 {
            let v = n / per
            return "\(v) \(v == 1 ? "volume" : "volumes")"
        }
        return "\(n) \(n == 1 ? "maço" : "maços")"
    }

    /// Valores do menu, incluindo o atual se vier de uma versão antiga.
    private func options(_ base: [Int], _ current: Int) -> [Int] {
        Array(Set(base + [current])).sorted()
    }
}
