// Ícone na barra de menus e o painel que abre por baixo dele.
//
// Painel próprio em vez do MenuBarExtra: o do SwiftUI descola-se da barra e
// deixa um fantasma quando o conteúdo muda de altura (ao adicionar um IQOS).
// Aqui o painel fica sempre preso por baixo do ícone, cresce para baixo e é
// vidro do sistema (NSGlassEffectView no macOS 26, material de menu antes).

import AppKit
import Observation
import SwiftUI

/// Painel que pode receber o teclado (para mudar o nome de um IQOS).
private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private struct SizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

final class StatusPanel: NSObject {
    private let model: AppModel
    private let openSettings: () -> Void
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var panel: KeyPanel?
    private var host: NSHostingView<AnyView>?
    private var size = CGSize(width: 340, height: 200)
    private var outsideClick: Any?
    private let radius: CGFloat = 18

    init(model: AppModel, openSettings: @escaping () -> Void) {
        self.model = model
        self.openSettings = openSettings
        super.init()
        if let button = item.button {
            button.target = self
            button.action = #selector(toggle)
            button.setAccessibilityLabel("IQOS Monitor")
        }
        trackSymbol()
    }

    /// Ícone da barra de menus: um maço de TEREA aberto. Fica com um ponto quando
    /// algum IQOS tem bateria fraca.
    private func trackSymbol() {
        let low = withObservationTracking { model.anyLowBattery } onChange: { [weak self] in
            DispatchQueue.main.async { self?.trackSymbol() }
        }
        item.button?.image = Self.packIcon(alert: low)
    }

    /// Desenhado em vetor como imagem modelo (preto e transparente), para o sistema
    /// o pintar bem em barras claras, escuras e quando está selecionado.
    static func packIcon(alert: Bool) -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.setStrokeColor(NSColor.black.cgColor)
            func round(_ r: CGRect, _ radius: CGFloat) -> CGPath {
                CGPath(roundedRect: r, cornerWidth: min(radius, r.width / 2), cornerHeight: min(radius, r.height / 2),
                       transform: nil)
            }
            // Tampa aberta, de pé atrás dos sticks (vê-se o lado de dentro).
            ctx.setLineWidth(1.1)
            ctx.addPath(round(CGRect(x: 4.75, y: 11.05, width: 8.5, height: 5.6), 0.9))
            ctx.strokePath()
            // Três sticks a sair do maço, com uma folga transparente à volta.
            let sticks = [5.5, 8.15, 10.8].map { CGRect(x: $0, y: 10, width: 1.7, height: 5) }
            ctx.setBlendMode(.clear)
            for r in sticks { ctx.addPath(round(r.insetBy(dx: -0.6, dy: -0.6), 1.4)) }
            ctx.fillPath()
            ctx.setBlendMode(.normal)
            for r in sticks { ctx.addPath(round(r, 0.85)) }
            ctx.fillPath()
            // Corpo do maço, com o colarinho interior e a faixa do nome recortados.
            ctx.addPath(round(CGRect(x: 3.6, y: 0.8, width: 10.8, height: 10.4), 1.6))
            ctx.fillPath()
            ctx.setBlendMode(.clear)
            ctx.fill(CGRect(x: 3.6, y: 8.6, width: 10.8, height: 0.8))
            ctx.addPath(round(CGRect(x: 6.5, y: 4.2, width: 5, height: 1.2), 0.6))
            ctx.fillPath()
            if alert {
                // Ponto de aviso no canto, recortado do maço.
                ctx.fillEllipse(in: CGRect(x: 11.4, y: -0.4, width: 7, height: 7))
                ctx.setBlendMode(.normal)
                ctx.fillEllipse(in: CGRect(x: 12.6, y: 0.8, width: 4.6, height: 4.6))
            }
            ctx.setBlendMode(.normal)
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = alert ? "IQOS Monitor, bateria fraca" : "IQOS Monitor"
        return img
    }

    var isOpen: Bool { panel?.isVisible == true }

    @objc func toggle() {
        isOpen ? close() : open()
    }

    func open() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        place(animated: false)
        NSApp.activate()
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { $0.duration = 0.12; panel.animator().alphaValue = 1 }
        item.button?.highlight(true)
        outsideClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] _ in self?.close()
        }
    }

    func close() {
        guard let panel, panel.isVisible else { return }
        if let m = outsideClick { NSEvent.removeMonitor(m) }
        outsideClick = nil
        item.button?.highlight(false)
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.1; panel.animator().alphaValue = 0 },
                                            completionHandler: { panel.orderOut(nil) })
    }

    private func makePanel() -> KeyPanel {
        let p = KeyPanel(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.isReleasedWhenClosed = false

        let root = MenuPanel(model: model, openSettings: { [weak self] in
            self?.close()
            self?.openSettings()
        })
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { g in Color.clear.preference(key: SizeKey.self, value: g.size) })
        .onPreferenceChange(SizeKey.self) { [weak self] s in self?.resize(to: s) }
        .frame(maxHeight: .infinity, alignment: .top)

        let host = NSHostingView(rootView: AnyView(root))
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        self.host = host

        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: host.frame)
            glass.cornerRadius = radius
            glass.contentView = host
            p.contentView = glass
        } else {
            let fx = NSVisualEffectView(frame: host.frame)
            fx.material = .menu
            fx.blendingMode = .behindWindow
            fx.state = .active
            fx.wantsLayer = true
            fx.layer?.cornerRadius = radius
            fx.layer?.masksToBounds = true
            fx.addSubview(host)
            p.contentView = fx
        }
        NotificationCenter.default.addObserver(self, selector: #selector(resigned),
                                               name: NSWindow.didResignKeyNotification, object: p)
        return p
    }

    @objc private func resigned() {
        // Fechar ao perder o foco, como um menu; o pedido de Bluetooth do sistema não conta.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, NSApp.keyWindow !== self.panel else { return }
            self.close()
        }
    }

    private func resize(to s: CGSize) {
        guard s.height > 1, abs(s.height - size.height) > 0.5 || abs(s.width - size.width) > 0.5 else { return }
        size = CGSize(width: max(s.width, 300), height: s.height)
        place(animated: isOpen)
    }

    /// Prende o painel por baixo do ícone; muda de altura sempre a partir do topo.
    private func place(animated: Bool) {
        guard let panel, let button = item.button, let window = button.window else { return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = (window.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        var x = anchor.midX - size.width / 2
        x = min(max(x, screen.minX + 8), screen.maxX - size.width - 8)
        let top = anchor.minY - 6
        let frame = NSRect(x: x, y: top - size.height, width: size.width, height: size.height)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.allowsImplicitAnimation = true
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }
}

/// Janela das Definições (aberta a partir do painel ou ao abrir a app outra vez).
final class SettingsWindow {
    private var window: NSWindow?
    private let model: AppModel

    init(model: AppModel) { self.model = model }

    func show() {
        let w = window ?? {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
            w.title = "Definições do IQOS Monitor"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            return w
        }()
        window = w
        NSApp.activate()
        w.makeKeyAndOrderFront(nil)
    }
}
