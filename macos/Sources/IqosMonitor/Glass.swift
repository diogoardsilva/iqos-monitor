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
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.primary.opacity(contrast == .increased ? 0.12 : 0.06))
            .overlay {
                if contrast == .increased {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.35), lineWidth: 1)
                }
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
