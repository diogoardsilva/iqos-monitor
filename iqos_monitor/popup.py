"""Janela no canto do ecrã ao tirar/pôr o holder (como a dos AirPods no iPhone).

A ilustração é desenhada em vetor por agora. Quando houver modelos 3D, a
animação passa a ser uma sequência de imagens renderizadas (ver HolderArt).
"""

from __future__ import annotations

from PySide6.QtCore import (
    QEasingCurve, QPoint, QPropertyAnimation, QRectF, Qt, QTimer, QVariantAnimation,
)
from PySide6.QtGui import (
    QColor, QFont, QGuiApplication, QLinearGradient, QPainter, QPainterPath, QPen,
)
from PySide6.QtWidgets import QWidget

from . import theme
from .theme import battery_color, font
from .tracker import DeviceState

SHOW_MS = 6500
MARGIN = 18


class HolderPopup(QWidget):
    def __init__(self) -> None:
        super().__init__(None, Qt.Tool | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
                         | Qt.WindowDoesNotAcceptFocus)
        self.setAttribute(Qt.WA_TranslucentBackground)
        self.setAttribute(Qt.WA_ShowWithoutActivating)
        self.setFixedSize(360, 176)
        self.dev: DeviceState | None = None
        self.leaving = True  # True: holder a sair; False: a entrar
        self.progress = 0.0  # posição na animação (0..1)
        self._closing = False

        self._slide = QPropertyAnimation(self, b"pos", self)
        self._slide.setDuration(420)
        self._slide.setEasingCurve(QEasingCurve.OutCubic)
        self._fade = QPropertyAnimation(self, b"windowOpacity", self)
        self._fade.setDuration(260)
        self._fade.finished.connect(self._after_fade)
        self._holder = QVariantAnimation(self, startValue=0.0, endValue=1.0, duration=2200)
        self._holder.valueChanged.connect(self._set_progress)
        self._timer = QTimer(self, singleShot=True, timeout=self.dismiss)

    # ---- API ---------------------------------------------------------------

    def show_for(self, dev: DeviceState, leaving: bool) -> None:
        self.dev, self.leaving = dev, leaving
        self.setAccessibleName(self._headline())
        geo = QGuiApplication.primaryScreen().availableGeometry()
        end = QPoint(geo.right() - self.width() - MARGIN, geo.bottom() - self.height() - MARGIN)
        self._closing = False
        if not self.isVisible():
            self.setWindowOpacity(0.0)
            self.move(end + QPoint(0, 40))
            self.show()
            self._fade.stop()
            self._fade.setStartValue(0.0)
            self._fade.setEndValue(1.0)
            self._fade.start()
            self._slide.setStartValue(self.pos())
            self._slide.setEndValue(end)
            self._slide.start()
        self._holder.stop()
        self._holder.setDuration(2200 if leaving else 900)
        QTimer.singleShot(250, self._holder.start)
        self.progress = 0.0
        self._timer.start(SHOW_MS)
        self.update()

    def dismiss(self) -> None:
        if not self.isVisible():
            return
        self._closing = True
        self._fade.stop()
        self._fade.setStartValue(self.windowOpacity())
        self._fade.setEndValue(0.0)
        self._fade.start()

    def mousePressEvent(self, _ev) -> None:
        self.dismiss()

    # ---- desenho -----------------------------------------------------------

    def _after_fade(self) -> None:
        if self._closing:
            self._closing = False
            self.hide()

    def _set_progress(self, v) -> None:
        self.progress = float(v)
        self.update()

    def _headline(self) -> str:
        d = self.dev
        if d is None:
            return ""
        if d.model.one_piece:
            return "Pronto" if (d.charger_pct or 0) > d.pct_per_stick else "Sem bateria"
        if not self.leaving:
            return "A carregar"
        return "Pronto" if d.holder_ready else "Ainda a carregar"

    def paintEvent(self, _ev) -> None:
        if self.dev is None:
            return
        p = theme.palette()
        d = self.dev
        qp = QPainter(self)
        qp.setRenderHint(QPainter.Antialiasing)

        card = QRectF(self.rect()).adjusted(6, 6, -6, -6)
        for i in range(6, 0, -1):  # sombra suave
            qp.setPen(Qt.NoPen)
            qp.setBrush(QColor(0, 0, 0, 5))
            qp.drawRoundedRect(card.adjusted(-i, -i + 2, i, i + 2), 22 + i, 22 + i)
        qp.setBrush(QColor(p.card))
        qp.setPen(QPen(QColor(p.separator), 0.6))
        qp.drawRoundedRect(card, 22, 22)

        mode = "one" if d.model.one_piece else "out" if self.leaving else "in"
        HolderArt.paint(qp, QRectF(card.left() + 14, card.top() + 12, 110, card.height() - 24),
                        self.progress, d.model.value, mode)

        x = card.left() + 140
        qp.setPen(QColor(p.secondary))
        qp.setFont(font(9))
        qp.drawText(QRectF(x, card.top() + 16, 200, 16), Qt.AlignLeft, d.alias)

        head = self._headline()
        ready = head == "Pronto"
        qp.setPen(QColor(p.green if ready else p.label))
        qp.setFont(font(17, QFont.DemiBold))
        qp.drawText(QRectF(x, card.top() + 34, 210, 30), Qt.AlignLeft, head)

        if d.model.one_piece:
            self._battery_row(qp, x, card.top() + 82, "Bateria", d.charger_pct)
            rem = d.sticks_remaining
            qp.setPen(QColor(p.secondary))
            qp.setFont(font(9))
            qp.drawText(QRectF(x, card.top() + 112, 210, 18), Qt.AlignLeft | Qt.AlignVCenter,
                        f"~{rem} cigarros com esta carga" if rem is not None else "")
        else:
            self._battery_row(qp, x, card.top() + 82, "Holder", d.holder_pct,
                              charging=not self.leaving)
            self._battery_row(qp, x, card.top() + 112, "Carregador", d.charger_pct)
        qp.end()

    def _battery_row(self, qp: QPainter, x: float, y: float, label: str, pct: int | None,
                     charging: bool = False) -> None:
        p = theme.palette()
        qp.setFont(font(9))
        qp.setPen(QColor(p.secondary))
        qp.drawText(QRectF(x, y, 80, 18), Qt.AlignLeft | Qt.AlignVCenter, label)
        # Pilha horizontal, como no ecrã dos AirPods.
        body = QRectF(x + 82, y + 3, 54, 12)
        qp.setPen(QPen(QColor(p.secondary), 1))
        qp.setBrush(Qt.NoBrush)
        qp.drawRoundedRect(body, 3.5, 3.5)
        qp.setBrush(QColor(p.secondary))
        qp.setPen(Qt.NoPen)
        qp.drawRoundedRect(QRectF(body.right() + 1.5, y + 7, 2.5, 4), 1, 1)
        if pct is not None:
            qp.setBrush(QColor(battery_color(p, pct)))
            qp.drawRoundedRect(QRectF(body.left() + 2, body.top() + 2,
                                      (body.width() - 4) * pct / 100, body.height() - 4), 2, 2)
        qp.setPen(QColor(p.label))
        qp.setFont(font(10, QFont.DemiBold))
        txt = "—" if pct is None else f"{'⚡' if charging else ''}{pct}%"
        qp.drawText(QRectF(body.right() + 10, y, 60, 18), Qt.AlignLeft | Qt.AlignVCenter, txt)


def _seg(t: float, a: float, b: float) -> float:
    """Progresso local (0..1) de uma fase [a, b] da animação, com ease-out."""
    x = min(max((t - a) / (b - a), 0.0), 1.0)
    return 1 - (1 - x) ** 3


class HolderArt:
    """Ilustração animada. t vai de 0 a 1.

    mode "out": o holder sai do carregador, o carregador desliza para o lado
                e um stick entra no holder.
    mode "in":  o holder volta para dentro do carregador.
    mode "one": modelos de peça única; só o stick a entrar.
    """

    STICK_W, STICK_H = 7.0, 48.0

    @classmethod
    def paint(cls, qp: QPainter, area: QRectF, t: float, model: str, mode: str) -> None:
        cx = area.center().x()
        if mode == "one":
            body = QRectF(cx - 13, area.top() + 34, 26, area.height() - 30)
            cls._stick(qp, cx, body.top(), _seg(t, 0.15, 0.9))
            cls._one(qp, body, model)
            return
        if mode == "in":
            rise, slide, stick = 1 - _seg(t, 0.0, 1.0), 0.0, 0.0
        else:
            rise, slide, stick = _seg(t, 0.0, 0.32), _seg(t, 0.32, 0.58), _seg(t, 0.58, 1.0)

        cw, ch = 62.0, 96.0
        case = QRectF(cx - cw / 2 - 52 * slide, area.bottom() - ch, cw, ch)
        hw, hh = 17.0, 80.0
        inside_top = area.bottom() - ch + 14
        out_top = inside_top - 52
        final_top = area.top() + 30  # holder ao centro, com espaço para o stick
        top = inside_top + (out_top - inside_top) * rise
        top += (final_top - out_top) * slide
        holder = QRectF(cx - hw / 2 + 10 * slide, top, hw, hh)

        if stick > 0:
            cls._stick(qp, holder.center().x(), holder.top(), stick)
        cls._holder(qp, holder)
        if slide < 1:
            qp.save()
            qp.setOpacity(1 - slide)
            cls._case(qp, case, model, led_on=rise > 0.5)
            qp.restore()

    @staticmethod
    def _holder(qp: QPainter, r: QRectF) -> None:
        g = QLinearGradient(r.topLeft(), r.topRight())
        g.setColorAt(0, QColor("#8E8E93"))
        g.setColorAt(0.45, QColor("#E5E5EA"))
        g.setColorAt(1, QColor("#636366"))
        qp.setPen(Qt.NoPen)
        qp.setBrush(g)
        qp.drawRoundedRect(r, r.width() / 2, r.width() / 2)
        qp.setBrush(QColor("#3A3A3C"))
        qp.drawEllipse(QRectF(r.center().x() - 4.5, r.top() + 3, 9, 6))
        qp.setBrush(QColor(0, 0, 0, 40))
        qp.drawRect(QRectF(r.left(), r.top() + 22, r.width(), 2))

    @staticmethod
    def _case(qp: QPainter, r: QRectF, model: str, led_on: bool) -> None:
        dark = theme.is_dark()
        prime = "PRIME" in model.upper()
        path = QPainterPath()
        path.addRoundedRect(r, 16, 16)
        g = QLinearGradient(r.topLeft(), r.bottomRight())
        if prime:
            g.setColorAt(0, QColor("#4A4A4E"))
            g.setColorAt(1, QColor("#1C1C1E"))
        else:
            g.setColorAt(0, QColor("#5A5D63" if dark else "#D9DCE1"))
            g.setColorAt(1, QColor("#3A3C40" if dark else "#A9AEB6"))
        qp.setBrush(g)
        qp.setPen(QPen(QColor(0, 0, 0, 50), 0.8))
        qp.drawPath(path)
        qp.setPen(Qt.NoPen)
        if prime:  # capa envolvente do ILUMA PRIME
            qp.setBrush(QColor("#2C2C2E"))
            qp.drawRect(QRectF(r.left(), r.top() + r.height() * 0.42, r.width(),
                               r.height() * 0.2))
        qp.setBrush(QColor("#30D158") if led_on else QColor(255, 255, 255, 140))
        qp.drawEllipse(QRectF(r.center().x() - 2.5, r.bottom() - 16, 5, 5))
        qp.setBrush(QColor(0, 0, 0, 90))
        qp.drawRoundedRect(QRectF(r.center().x() - 10.5, r.top() + 4, 21, 5), 2.5, 2.5)

    @staticmethod
    def _one(qp: QPainter, r: QRectF, model: str) -> None:
        g = QLinearGradient(r.topLeft(), r.topRight())
        g.setColorAt(0, QColor("#3A3A3C"))
        g.setColorAt(0.5, QColor("#8E8E93"))
        g.setColorAt(1, QColor("#2C2C2E"))
        qp.setPen(Qt.NoPen)
        qp.setBrush(g)
        qp.drawRoundedRect(r, 11, 11)
        qp.setBrush(QColor("#1C1C1E"))
        qp.drawEllipse(QRectF(r.center().x() - 5, r.top() + 4, 10, 6))
        qp.setBrush(QColor("#30D158"))
        qp.drawEllipse(QRectF(r.center().x() - 2.5, r.top() + 30, 5, 5))

    @classmethod
    def _stick(cls, qp: QPainter, cx: float, holder_top: float, k: float) -> None:
        """Stick TEREA a descer para o topo do holder (k: 0 longe, 1 encaixado)."""
        w, h = cls.STICK_W, cls.STICK_H
        inserted_top = holder_top - 22  # fica 22 px de fora, como o filtro
        top = inserted_top - 28 * (1 - k)
        r = QRectF(cx - w / 2, top, w, h)
        qp.save()
        qp.setOpacity(min(k * 2.5, 1.0))
        qp.setPen(QPen(QColor(0, 0, 0, 45), 0.6))
        qp.setBrush(QColor("#F5F1E8"))
        qp.drawRoundedRect(r, 2, 2)
        qp.setPen(Qt.NoPen)
        qp.setBrush(QColor("#D9A441"))  # filtro
        qp.drawRect(QRectF(r.left() + 0.4, r.top() + 0.4, w - 0.8, 13))
        qp.setBrush(QColor("#B4472E"))  # faixa de cor do sabor
        qp.drawRect(QRectF(r.left() + 0.4, r.top() + 13, w - 0.8, 3))
        qp.restore()
