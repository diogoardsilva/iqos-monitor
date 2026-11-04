// Módulo do tabaco no painel da barra de menus: quanto resta, o maço aberto e
// a compra. Segue o desenho dos módulos dos IQOS (ver Views.swift): fundo
// neutro dentro do vidro do painel, controlos redondos de vidro.

import IqosCore
import SwiftUI

struct StockModule: View {
    var model: AppModel
    /// nil = a mostrar o estado; .buy / .correct = a editar dentro do módulo.
    @State private var editing: Mode?
    @State private var cartons = 1
    @State private var packs = 0
    @State private var sticks = 0

    enum Mode { case buy, correct }

    var body: some View {
        let st = model.settings.stock
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Tabaco").font(.headline)
                    Text(subtitle(st))
                        .font(.subheadline)
                        .foregroundStyle(low(st) ? Color.orange : Color.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 6)
                if editing == nil { actionsMenu(st) }
            }

            if let mode = editing {
                editor(mode, st)
            } else if st.tracking {
                HStack(alignment: .center, spacing: 14) {
                    PackGauge(left: st.openPackLeft, size: st.packSize,
                              warn: st.packWarnSticks > 0 && st.openPackLeft <= st.packWarnSticks)
                    Spacer(minLength: 0)
                    Count(value: "\(st.closedPacks)", caption: "por abrir")
                    Count(value: st.daysLeft(today: Date()).map { "~\($0)" } ?? "—", caption: "dias")
                }
            } else {
                Button("Registar compra…") { start(.buy, st) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
            }
        }
        .padding(12)
        .background(ModuleBackground())
        .animation(.smooth(duration: 0.25), value: editing)
    }

    private func subtitle(_ st: Stock) -> String {
        guard st.tracking else { return "Diga quanto tabaco tem e a app avisa quando estiver a acabar." }
        return st.sticksLeft == 0 ? "Acabou o tabaco" : "Resta \(st.describe())"
    }

    private func low(_ st: Stock) -> Bool {
        guard let left = st.sticksLeft else { return false }
        return left == 0 || (st.lowStockPacks > 0 && left <= st.lowStockSticks)
    }

    private func actionsMenu(_ st: Stock) -> some View {
        Menu {
            Button("Comprei tabaco…") { start(.buy, st) }
            if st.tracking {
                Button("Corrigir quanto tenho…") { start(.correct, st) }
                Divider()
                Button("Deixar de contar", role: .destructive) { model.stopStock() }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 16, height: 16)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .glassControl()
        .fixedSize()
        .accessibilityLabel("Ações do tabaco")
    }

    private func start(_ mode: Mode, _ st: Stock) {
        if mode == .correct, let left = st.sticksLeft {
            cartons = left / st.cartonSize
            packs = left % st.cartonSize / st.packSize
            sticks = left % st.packSize
        } else {
            cartons = 1
            packs = 0
            sticks = 0
        }
        editing = mode
    }

    @ViewBuilder
    private func editor(_ mode: Mode, _ st: Stock) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(mode == .buy ? "Quanto comprou?" : "Quanto tem agora?")
                .font(.callout.weight(.semibold))
            Stepper("\(cartons) \(cartons == 1 ? "volume" : "volumes")", value: $cartons, in: 0...50)
            Stepper("\(packs) \(packs == 1 ? "maço" : "maços")", value: $packs, in: 0...99)
            if mode == .correct {
                Stepper("\(sticks) \(sticks == 1 ? "stick solto" : "sticks soltos")",
                        value: $sticks, in: 0...max(st.packSize - 1, 0))
            }
            Text("1 maço = \(st.packSize) sticks · 1 volume = \(st.packsPerCarton) maços")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancelar") { editing = nil }
                    .keyboardShortcut(.cancelAction)
                Button(mode == .buy ? "Adicionar" : "Guardar") {
                    if mode == .buy {
                        model.buyStock(cartons: cartons, packs: packs)
                    } else {
                        model.setStock(cartons: cartons, packs: packs, sticks: sticks)
                    }
                    editing = nil
                }
                .keyboardShortcut(.defaultAction)
                .disabled(mode == .buy && cartons == 0 && packs == 0)
            }
            .controlSize(.small)
            .padding(.top, 2)
        }
        .font(.callout.monospacedDigit())
    }
}

/// O maço aberto: um traço por stick, cheio para os que ainda lá estão.
struct PackGauge: View {
    var left: Int
    var size: Int
    var warn: Bool

    var body: some View {
        let color: Color = left == 0 ? .secondary : warn ? .orange : .green
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: size > 20 ? 1 : 2) {
                ForEach(0..<max(size, 1), id: \.self) { i in
                    Capsule()
                        .fill(i < left ? color : Color.primary.opacity(0.12))
                        .frame(width: size > 20 ? 2.5 : 4, height: 22)
                }
            }
            .animation(.smooth(duration: 0.4), value: left)
            Text("\(left) no maço aberto")
                .font(.caption)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Maço aberto: \(left) de \(size) sticks")
    }
}
