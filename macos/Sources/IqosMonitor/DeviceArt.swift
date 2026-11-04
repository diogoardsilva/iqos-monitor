// Ilustrações vetoriais dos aparelhos, desenhadas em Canvas (sem logótipos).
// Mesmo desenho de iqos_monitor/art.py: proporções aproximadas dos aparelhos
// reais e as cores de série de cada modelo.

import IqosCore
import SwiftUI

struct Finish {
    var base: Color
    var light: Color
    var dark: Color
    var wrap: Color?  // capa envolvente dos PRIME
    var led: Color = .white

    static func hex(_ v: UInt32) -> Color {
        Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255,
              blue: Double(v & 0xFF) / 255)
    }

    static func of(_ model: Model) -> Finish {
        switch model {
        case .ilumaPrime: return Finish(base: hex(0x3C3E42), light: hex(0x7A7D82), dark: hex(0x141517),
                                        wrap: hex(0x26272A))  // Obsidian
        case .ilumaI: return Finish(base: hex(0x7FA3BF), light: hex(0xC9DCEA), dark: hex(0x3F5D74))  // Breeze
        case .ilumaIPrime: return Finish(base: hex(0x3F6157), light: hex(0x86A79C), dark: hex(0x1C2E28),
                                         wrap: hex(0x2C463E))  // Jade
        case .ilumaOne: return Finish(base: hex(0x4F7FA3), light: hex(0xA9C8DF), dark: hex(0x233F55))  // Azure
        default: return Finish(base: hex(0xA9ABAE), light: hex(0xE4E5E7), dark: hex(0x5E6064))  // Pebble Grey
        }
    }

    /// Cor de destaque do aparelho, usada para tingir o vidro.
    var accent: Color { base }
}

enum ArtKind { case charger, holder, one, stick }

/// Desenha uma peça num GraphicsContext em coordenadas do SVG original.
struct ArtPainter {
    var ctx: GraphicsContext
    var origin: CGPoint
    var scale: CGFloat

    static let viewBox: [ArtKind: CGSize] = [
        .charger: CGSize(width: 100, height: 214), .holder: CGSize(width: 30, height: 200),
        .one: CGSize(width: 64, height: 246), .stick: CGSize(width: 14, height: 90),
    ]
    // Altura de cada peça à mesma escala (~1.2 px/mm), como na versão Windows.
    static let height: [ArtKind: CGFloat] = [.charger: 120, .holder: 114, .one: 132, .stick: 52]

    func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: origin.x + x * scale, y: origin.y + y * scale, width: w * scale, height: h * scale)
    }

    func round(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ rx: CGFloat) -> Path {
        Path(roundedRect: r(x, y, w, h), cornerRadius: min(rx * scale, min(w, h) * scale / 2))
    }

    func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> Path {
        Path(ellipseIn: r(cx - rx, cy - ry, rx * 2, ry * 2))
    }

    func horizontal(_ stops: [Gradient.Stop], _ p: Path) -> GraphicsContext.Shading {
        let b = p.boundingRect
        return .linearGradient(Gradient(stops: stops), startPoint: CGPoint(x: b.minX, y: b.midY),
                               endPoint: CGPoint(x: b.maxX, y: b.midY))
    }

    func vertical(_ stops: [Gradient.Stop], _ p: Path) -> GraphicsContext.Shading {
        let b = p.boundingRect
        return .linearGradient(Gradient(stops: stops), startPoint: CGPoint(x: b.midX, y: b.minY),
                               endPoint: CGPoint(x: b.midX, y: b.maxY))
    }

    /// Corpo arredondado iluminado da esquerda.
    func cylinder(_ f: Finish, _ p: Path) {
        ctx.fill(p, with: horizontal([
            .init(color: f.dark, location: 0), .init(color: f.base, location: 0.10),
            .init(color: f.light, location: 0.30), .init(color: f.base, location: 0.42),
            .init(color: f.base, location: 0.86), .init(color: f.dark, location: 1),
        ], p))
    }

    func shade(_ p: Path) {
        ctx.fill(p, with: vertical([
            .init(color: .white.opacity(0.22), location: 0), .init(color: .white.opacity(0), location: 0.25),
            .init(color: .black.opacity(0), location: 0.75), .init(color: .black.opacity(0.28), location: 1),
        ], p))
    }

    func hole(_ p: Path) {
        ctx.fill(p, with: vertical([.init(color: Finish.hex(0x050505), location: 0),
                                    .init(color: Finish.hex(0x2A2A2C), location: 1)], p))
    }

    func ground(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) {
        let rect = r(cx - rx, cy - ry, rx * 2, ry * 2)
        ctx.fill(Path(ellipseIn: rect), with: .radialGradient(
            Gradient(colors: [.black.opacity(0.35), .black.opacity(0)]),
            center: CGPoint(x: rect.midX, y: rect.midY), startRadius: 0, endRadius: rect.width / 2))
    }

    func charger(_ f: Finish) {
        ground(50, 206, 46, 6)
        let body = round(4, 6, 92, 198, 30)
        cylinder(f, body)
        shade(body)
        ctx.stroke(round(4.6, 6.6, 90.8, 196.8, 29.4), with: .color(.white.opacity(0.35)),
                   lineWidth: 0.9 * scale)
        ctx.fill(ellipse(50, 13, 34, 4), with: .color(.white.opacity(0.18)))
        hole(round(32, 9, 36, 12, 6))
        ctx.fill(round(33, 18.5, 34, 1, 0.5), with: .color(.white.opacity(0.18)))
        if let w = f.wrap {
            let wf = Finish(base: w, light: f.base, dark: Finish.hex(0x0A0A0A))
            var wrap = round(2, 100, 96, 104, 30)
            wrap.addRect(r(2, 100, 96, 30))
            cylinder(wf, wrap)
            shade(round(2, 100, 96, 104, 30))
            ctx.fill(Path(r(2, 100, 96, 1.2)), with: .color(.black.opacity(0.35)))
            var seam = Path()
            seam.move(to: CGPoint(x: r(7, 105, 0, 0).minX, y: r(7, 105, 0, 0).minY))
            seam.addLine(to: CGPoint(x: r(93, 105, 0, 0).minX, y: r(93, 105, 0, 0).minY))
            ctx.stroke(seam, with: .color(.white.opacity(0.22)),
                       style: StrokeStyle(lineWidth: 0.8 * scale, dash: [2.5 * scale, 2 * scale]))
        }
        ctx.fill(round(45, 186, 10, 2.6, 1.3), with: .color(f.led.opacity(0.8)))
    }

    func holder(_ f: Finish) {
        let cap: [Gradient.Stop] = [
            .init(color: Finish.hex(0x4A4A4D), location: 0), .init(color: Finish.hex(0xE9E9EC), location: 0.3),
            .init(color: Finish.hex(0xB8B8BD), location: 0.45), .init(color: Finish.hex(0x3E3E42), location: 1),
        ]
        let body = round(3, 0, 24, 200, 12)
        cylinder(f, body)
        shade(body)
        var top = round(3, 0, 24, 34, 12)
        top.addRect(r(3, 22, 24, 12))
        ctx.fill(top, with: horizontal(cap, top))
        ctx.fill(Path(r(3, 33.5, 24, 1.4)), with: .color(.black.opacity(0.45)))
        ctx.fill(Path(r(3, 35, 24, 0.8)), with: .color(.white.opacity(0.35)))
        hole(ellipse(15, 5, 7.5, 3.2))
        ctx.fill(ellipse(15, 4.2, 4.2, 1.6), with: .color(.black))
        ctx.fill(round(13.6, 48, 2.8, 26, 1.4), with: .color(f.led.opacity(0.55)))
        ctx.fill(round(3.6, 2, 1.2, 190, 0.6), with: .color(.white.opacity(0.18)))
    }

    func one(_ f: Finish) {
        ground(32, 240, 30, 5)
        let body = round(2, 0, 60, 236, 26)
        cylinder(f, body)
        shade(body)
        var top = round(2, 0, 60, 62, 26)
        top.addRect(r(2, 40, 60, 22))
        ctx.fill(top, with: horizontal([
            .init(color: f.dark, location: 0), .init(color: f.light, location: 0.3),
            .init(color: f.base, location: 0.5), .init(color: f.dark, location: 1),
        ], top))
        ctx.fill(Path(r(2, 61.5, 60, 1.6)), with: .color(.black.opacity(0.4)))
        ctx.fill(Path(r(2, 63.1, 60, 0.9)), with: .color(.white.opacity(0.3)))
        hole(ellipse(32, 9, 10, 4))
        ctx.fill(ellipse(32, 8.2, 5.5, 2), with: .color(.black))
        ctx.stroke(round(2.6, 0.6, 58.8, 234.8, 25.4), with: .color(.white.opacity(0.3)),
                   lineWidth: 0.9 * scale)
        for (y, a) in [(92.0, 0.85), (100.0, 0.85), (108.0, 0.35)] {
            ctx.fill(ellipse(32, y, 2, 2), with: .color(f.led.opacity(a)))
        }
    }

    func stick() {
        let paper = round(1, 1, 12, 88, 1.5)
        ctx.fill(paper, with: horizontal([
            .init(color: Finish.hex(0xBDB7AA), location: 0), .init(color: .white, location: 0.3),
            .init(color: Finish.hex(0xF1ECE2), location: 0.6), .init(color: Finish.hex(0xA9A396), location: 1),
        ], paper))
        let band = Path(r(1, 26, 12, 5))
        ctx.fill(band, with: horizontal([
            .init(color: Finish.hex(0x7A2A1A), location: 0), .init(color: Finish.hex(0xD2643F), location: 0.3),
            .init(color: Finish.hex(0x6E2416), location: 1),
        ], band))
        ctx.fill(Path(r(1, 34, 12, 0.6)), with: .color(.black.opacity(0.12)))
        ctx.fill(ellipse(7, 1.8, 5.6, 1.6), with: .color(Finish.hex(0xE9E3D6)))
        ctx.fill(ellipse(7, 1.8, 2.4, 0.8), with: .color(Finish.hex(0xBFB49C)))
    }

    /// Desenha a peça centrada em xCenter, com o topo em `top` e a altura dada.
    static func draw(_ ctx: GraphicsContext, _ kind: ArtKind, _ model: Model, xCenter: CGFloat,
                     top: CGFloat, height: CGFloat) {
        let vb = viewBox[kind]!
        let s = height / vb.height
        let p = ArtPainter(ctx: ctx, origin: CGPoint(x: xCenter - vb.width * s / 2, y: top), scale: s)
        let f = Finish.of(model)
        switch kind {
        case .charger: p.charger(f)
        case .holder: p.holder(f)
        case .one: p.one(f)
        case .stick: p.stick()
        }
    }
}

/// Desenho estático de uma peça, à altura dada (para o centro dos anéis).
struct DeviceGlyph: View {
    var kind: ArtKind
    var model: Model
    var height: CGFloat

    var body: some View {
        let vb = ArtPainter.viewBox[kind]!
        Canvas { ctx, size in
            ArtPainter.draw(ctx, kind, model, xCenter: size.width / 2, top: 0, height: size.height)
        }
        .frame(width: height * vb.width / vb.height, height: height)
        .accessibilityHidden(true)
    }
}

/// Progresso local (0...1) de uma fase [a, b] da animação, com ease-out.
func segment(_ t: Double, _ a: Double, _ b: Double) -> Double {
    let x = min(max((t - a) / (b - a), 0), 1)
    return 1 - pow(1 - x, 3)
}

/// Ilustração animada da janela do canto. t vai de 0 a 1.
/// - out: o holder sai do carregador, o carregador desliza para o lado e um stick entra.
/// - back: o holder volta para dentro do carregador.
/// - one: modelos de peça única; só o stick a entrar.
enum HolderAnimation {
    enum Mode { case out, back, one }

    static func paint(_ ctx: GraphicsContext, area: CGRect, t: Double, model: Model, mode: Mode) {
        let h = ArtPainter.height
        let cx = area.midX
        let ground = area.maxY - 2
        if mode == .one {
            let top = ground - h[.one]!
            stick(ctx, model, cx: cx, entryTop: top + 1, k: segment(t, 0.15, 0.9))
            ArtPainter.draw(ctx, .one, model, xCenter: cx, top: top, height: h[.one]!)
            return
        }
        let phases: (Double, Double, Double) = mode == .back
            ? (1 - segment(t, 0, 1), 0, 0)
            : (segment(t, 0, 0.3), segment(t, 0.3, 0.6), segment(t, 0.6, 1))
        let (rise, slide, stickK) = phases
        let chargerTop = ground - h[.charger]!
        let inside = chargerTop + 3, out = chargerTop - 40
        let final = ground - h[.holder]! - 8
        let top = inside + (out - inside) * rise + (final - out) * slide

        if slide > 0 {  // sombra do holder no "chão" quando fica sozinho
            var c = ctx
            c.opacity = slide
            let rect = CGRect(x: cx - 16, y: ground - 6, width: 32, height: 6)
            c.fill(Path(ellipseIn: rect), with: .radialGradient(
                Gradient(colors: [.black.opacity(0.27), .black.opacity(0)]),
                center: CGPoint(x: rect.midX, y: rect.midY), startRadius: 0, endRadius: 16))
        }
        if slide <= 0.02 {
            // O holder sai pela abertura: só se vê a parte acima do meio da abertura.
            ArtPainter.draw(ctx, .charger, model, xCenter: cx, top: chargerTop, height: h[.charger]!)
            var c = ctx
            let slotMid = chargerTop + h[.charger]! * 15 / 214
            c.clip(to: Path(CGRect(x: area.minX - 20, y: area.minY - 60, width: area.width + 40,
                                   height: slotMid - area.minY + 60)))
            ArtPainter.draw(c, .holder, model, xCenter: cx, top: top, height: h[.holder]!)
            return
        }
        if stickK > 0 { stick(ctx, model, cx: cx, entryTop: top, k: stickK) }
        ArtPainter.draw(ctx, .holder, model, xCenter: cx, top: top, height: h[.holder]!)
        var c = ctx
        c.opacity = 1 - slide
        ArtPainter.draw(c, .charger, model, xCenter: cx - 62 * slide, top: chargerTop, height: h[.charger]!)
    }

    /// Stick TEREA a descer até ficar com o filtro de fora (k: 0 longe, 1 encaixado).
    static func stick(_ ctx: GraphicsContext, _ model: Model, cx: CGFloat, entryTop: CGFloat, k: Double) {
        var c = ctx
        c.opacity = min(k * 2.5, 1)
        let final = entryTop - 26
        ArtPainter.draw(c, .stick, model, xCenter: cx, top: final - 30 * (1 - k), height: ArtPainter.height[.stick]!)
    }
}
