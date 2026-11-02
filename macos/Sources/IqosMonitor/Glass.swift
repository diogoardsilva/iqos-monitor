// Liquid Glass: usa as APIs do macOS 26 (glassEffect, GlassEffectContainer,
// estilos de botão .glass) e recua para materiais translúcidos no macOS 14/15.

import AppKit
import SwiftUI

extension View {
    /// Painel de vidro com cantos contínuos, opcionalmente tingido com a cor do aparelho.
    @ViewBuilder
    func glassPanel(cornerRadius: CGFloat = 26, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            let base = interactive ? Glass.regular.interactive() : Glass.regular
            self.glassEffect(tint.map { base.tint($0.opacity(0.18)) } ?? base,
                             in: .rect(cornerRadius: cornerRadius))
        } else {
            self
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .background((tint ?? .clear).opacity(0.10),
                            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 0.6))
                .shadow(color: .black.opacity(0.10), radius: 14, y: 6)
        }
    }

    /// Botão de vidro (ou de vidro em destaque, para a ação principal).
    @ViewBuilder
    func glassButton(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent { self.buttonStyle(.glassProminent) } else { self.buttonStyle(.glass) }
        } else {
            if prominent { self.buttonStyle(.borderedProminent) } else { self.buttonStyle(.bordered) }
        }
    }
}

/// Agrupa painéis de vidro para se fundirem e animarem juntos (macOS 26).
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

/// Fundo translúcido da janela: desfoca o que está por trás (ambiente de trabalho).
struct WindowBackdrop: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .followsWindowActiveState
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
    }
}

/// Manchas de cor suaves por trás dos cartões, para o vidro ter o que refratar.
struct AmbientBackground: View {
    var colors: [Color]
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                WindowBackdrop()
                ForEach(Array(colors.prefix(4).enumerated()), id: \.offset) { i, c in
                    let spots: [(CGFloat, CGFloat)] = [(0.15, 0.12), (0.9, 0.38), (0.2, 0.72), (0.85, 0.95)]
                    Circle()
                        .fill(c.opacity(scheme == .dark ? 0.45 : 0.35))
                        .frame(width: w * 0.9, height: w * 0.9)
                        .blur(radius: 70)
                        .position(x: w * spots[i].0, y: h * spots[i].1)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Cores do sistema para o nível de bateria.
func batteryColor(_ pct: Int?) -> Color {
    guard let pct else { return .secondary }
    return pct <= 20 ? .red : pct <= 40 ? .orange : .green
}
