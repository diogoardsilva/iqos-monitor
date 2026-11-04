// Cores e pequenos estilos partilhados.
//
// Regra da Apple para o Liquid Glass: o vidro é só para a camada funcional que
// flutua por cima do conteúdo (barras, menus, painéis). O painel da barra de
// menus e a janela do canto já são vidro do sistema; o que está lá dentro é
// conteúdo e usa preenchimentos neutros, nunca vidro sobre vidro.

import SwiftUI

/// Cores do sistema para o nível de bateria (a cor só reforça; o valor está sempre escrito).
func batteryColor(_ pct: Int?) -> Color {
    guard let pct else { return .secondary }
    return pct <= 20 ? .red : pct <= 40 ? .orange : .green
}

/// Fundo dos módulos dentro do painel, como os do Centro de Controlo.
struct ModuleBackground: View {
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        shape
            .fill(Color.primary.opacity(contrast == .increased ? 0.12 : 0.05))
            .overlay {
                // Aresta com luz de cima, para o módulo assentar no vidro do painel.
                shape.strokeBorder(
                    contrast == .increased
                        ? AnyShapeStyle(Color.primary.opacity(0.35))
                        : AnyShapeStyle(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.04)],
                                                       startPoint: .top, endPoint: .bottom)),
                    lineWidth: contrast == .increased ? 1 : 0.7)
            }
    }
}

/// Linha de menu: ocupa a largura toda e realça ao passar o ponteiro, como num menu do macOS.
struct MenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MenuRow(configuration: configuration)
    }

    private struct MenuRow: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
                .foregroundStyle(enabled ? Color.primary : Color.secondary)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(configuration.isPressed ? 0.16 : hovering && enabled ? 0.09 : 0))
                )
                .onHover { hovering = $0 }
        }
    }
}

extension View {
    /// Botão redondo de vidro para os controlos do painel (+, ⋯). Os controlos são
    /// camada funcional, por isso levam vidro interativo no macOS 26.
    @ViewBuilder
    func glassControl() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass).buttonBorderShape(.circle)
        } else {
            self.buttonStyle(.borderless)
        }
    }
}
