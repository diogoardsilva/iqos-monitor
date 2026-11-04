// Janela no canto do ecrã ao tirar/pôr o holder (como a dos AirPods no iPhone).
// No Mac aparece no canto superior direito, onde aparecem as notificações,
// num painel de vidro que não rouba o foco.

import AppKit
import IqosCore
import SwiftUI

final class CornerPopup {
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?
    private let size = NSSize(width: 360, height: 136)  // tamanho de uma notificação
    static let showSeconds = 6.5

    func show(_ d: DeviceState, mode: HolderAnimation.Mode) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let view = PopupView(device: d, mode: mode, start: Date()) { [weak self] in self?.dismiss() }
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: host.frame)
            glass.cornerRadius = 24
            // Vidro regular com um véu do fundo da janela, como os avisos do sistema:
            // o texto lê-se bem mesmo sobre um fundo claro ou cheio de cor.
            glass.tintColor = NSColor.windowBackgroundColor.withAlphaComponent(0.55)
            glass.contentView = host
            panel.contentView = glass
        } else {
            let fx = NSVisualEffectView(frame: host.frame)
            fx.material = .popover
            fx.blendingMode = .behindWindow
            fx.state = .active
            fx.wantsLayer = true
            fx.layer?.cornerRadius = 24
            fx.layer?.masksToBounds = true
            host.autoresizingMask = [.width, .height]
            fx.addSubview(host)
            panel.contentView = fx
        }

        guard let screen = NSScreen.main?.visibleFrame else { return }
        let end = NSPoint(x: screen.maxX - size.width - 12, y: screen.maxY - size.height - 8)
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.setFrameOrigin(NSPoint(x: end.x + 40, y: end.y))
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.42
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1.0)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(NSRect(origin: end, size: size), display: true)
        }
        NSAccessibility.post(element: panel, notification: .announcementRequested,
                             userInfo: [.announcement: "\(d.alias): \(PopupView.headline(d, mode))"])
        hideWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.dismiss() }
        hideWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.showSeconds, execute: w)
    }

    func dismiss() {
        guard let panel, panel.isVisible else { return }
        hideWork?.cancel()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.26
            panel.animator().alphaValue = 0
        }, completionHandler: { panel.orderOut(nil) })
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.isMovableByWindowBackground = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        return p
    }
}

struct PopupView: View {
    var device: DeviceState
    var mode: HolderAnimation.Mode
    var start: Date
    var onClose: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func headline(_ d: DeviceState, _ mode: HolderAnimation.Mode) -> String {
        if d.model.onePiece {
            return Double(d.chargerPct ?? 0) > d.pctPerStick ? "Pronto" : "Sem bateria"
        }
        if mode == .back { return "A carregar" }
        return d.holderReady ? "Pronto" : "Ainda a carregar"
    }

    var body: some View {
        let head = Self.headline(device, mode)
        HStack(spacing: 12) {
            TimelineView(.animation) { tl in
                let elapsed = tl.date.timeIntervalSince(start) - 0.25
                let duration = mode == .back ? 0.9 : 2.2
                let t = reduceMotion ? 1 : min(max(elapsed / duration, 0), 1)
                Canvas { ctx, size in
                    // A animação foi desenhada numa área de 120 × 174; reduz para caber.
                    let k = min(size.height / 174, size.width / 120)
                    var c = ctx
                    c.scaleBy(x: k, y: k)
                    HolderAnimation.paint(c, area: CGRect(x: 0, y: 0, width: size.width / k, height: size.height / k),
                                          t: t, model: device.model, mode: mode)
                }
            }
            .frame(width: 78)
            .padding(.vertical, 8)

            VStack(alignment: .leading, spacing: 3) {
                Text(device.alias)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(head)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(head == "Pronto" ? Color.green : Color.primary)
                    .padding(.bottom, 4)
                if device.model.onePiece {
                    BatteryRow(label: "Bateria", pct: device.chargerPct)
                    if let rem = device.sticksRemaining {
                        Text("~\(rem) cigarros com esta carga")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    BatteryRow(label: "Holder", pct: device.holderPct, charging: mode == .back)
                    BatteryRow(label: "Carregador", pct: device.chargerPct)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 12)
        .padding(.trailing, 16)
        .frame(width: 360, height: 136)
        .contentShape(Rectangle())
        .onTapGesture(perform: onClose)
        .accessibilityElement(children: .combine)
    }
}

/// Pilha horizontal, como no ecrã dos AirPods.
struct BatteryRow: View {
    var label: String
    var pct: Int?
    var charging = false

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .leading)
            HStack(spacing: 1.5) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(.secondary, lineWidth: 1)
                    GeometryReader { g in
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .fill(batteryColor(pct))
                            .frame(width: max((g.size.width - 4) * Double(pct ?? 0) / 100, 0))
                            .padding(2)
                    }
                }
                .frame(width: 44, height: 12)
                RoundedRectangle(cornerRadius: 1)
                    .fill(.secondary)
                    .frame(width: 2.5, height: 5)
            }
            Text(pct.map { "\(charging ? "⚡︎" : "")\($0)%" } ?? "—")
                .font(.callout.weight(.semibold).monospacedDigit())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(pct.map { "\($0) por cento" } ?? "sem leitura")")
    }
}
