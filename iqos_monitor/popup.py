"""Janela no canto do ecrã ao tirar/pôr o holder (como a dos AirPods no iPhone).

A ilustração é desenhada em vetor por agora. Quando houver modelos 3D, a
animação passa a ser uma sequência de imagens renderizadas (ver HolderArt).
"""

from __future__ import annotations

from PySide6.QtCore import (
    QEasingCurve, QPoint, QPropertyAnimation, QRectF, Qt, QTimer, QVariantAnimation,
)
from PySide6.QtGui import (
    QColor, QFont, QGuiApplication, QPainter, QPen, QRadialGradient,
)
from PySide6.QtWidgets import QWidget

from . import art, theme
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
        self.setFixedSize(380, 200)
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
        HolderArt.paint(qp, QRectF(card.left() + 16, card.top() + 10, 120, card.height() - 22),
                        self.progress, d.model.value, mode)

        x = card.left() + 150
        qp.setPen(QColor(p.secondary))
        qp.setFont(font(9))
        qp.drawText(QRectF(x, card.top() + 30, 200, 16), Qt.AlignLeft, d.alias)

        head = self._headline()
        ready = head == "Pronto"
        qp.setPen(QColor(p.green if ready else p.label))
        qp.setFont(font(17, QFont.DemiBold))
        qp.drawText(QRectF(x, card.top() + 48, 210, 30), Qt.AlignLeft, head)

        if d.model.one_piece:
            self._battery_row(qp, x, card.top() + 98, "Bateria", d.charger_pct)
            rem = d.sticks_remaining
            qp.setPen(QColor(p.secondary))
            qp.setFont(font(9))
            qp.drawText(QRectF(x, card.top() + 128, 210, 18), Qt.AlignLeft | Qt.AlignVCenter,
                        f"~{rem} cigarros com esta carga" if rem is not None else "")
        else:
            self._battery_row(qp, x, card.top() + 98, "Holder", d.holder_pct,
                              charging=not self.leaving)
            self._battery_row(qp, x, card.top() + 128, "Carregador", d.charger_pct)
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
    """Ilustração animada (ver art.py). t vai de 0 a 1.

    mode "out": o holder sai do carregador, o carregador desliza para o lado
                e um stick entra no holder.
    mode "in":  o holder volta para dentro do carregador.
    mode "one": modelos de peça única; só o stick a entrar.
    """

    @classmethod
    def paint(cls, qp: QPainter, area: QRectF, t: float, model: str, mode: str) -> None:
        cx = area.center().x()
        ground = area.bottom() - 2
        if mode == "one":
            top = ground - art.ONE_H
            cls._stick(qp, model, cx, top + 1, _seg(t, 0.15, 0.9))
            art.draw(qp, "one", model, cx, top, art.ONE_H)
            return
        if mode == "in":
            rise, slide, stick = 1 - _seg(t, 0.0, 1.0), 0.0, 0.0
        else:
            rise, slide, stick = _seg(t, 0.0, 0.3), _seg(t, 0.3, 0.6), _seg(t, 0.6, 1.0)

        charger_top = ground - art.CHARGER_H
        inside, out = charger_top + 3, charger_top - 40
        final = ground - art.HOLDER_H - 8  # holder de pé, ao centro
        top = inside + (out - inside) * rise + (final - out) * slide

        if slide > 0:  # sombra do holder no "chão" quando fica sozinho
            qp.save()
            qp.setOpacity(slide)
            qp.setPen(Qt.NoPen)
            g = QRadialGradient(cx, ground - 3, 16)
            g.setColorAt(0, QColor(0, 0, 0, 70))
            g.setColorAt(1, QColor(0, 0, 0, 0))
            qp.setBrush(g)
            qp.drawEllipse(QRectF(cx - 16, ground - 6, 32, 6))
            qp.restore()
        if slide <= 0.02:
            # O holder sai pela abertura: desenha o carregador e por cima só a parte
            # do holder acima do meio da abertura.
            art.draw(qp, "charger", model, cx, charger_top, art.CHARGER_H)
            qp.save()
            slot_mid = charger_top + art.CHARGER_H * 15 / 214
            qp.setClipRect(QRectF(area.left() - 20, area.top() - 40, area.width() + 40,
                                  slot_mid - area.top() + 40))
            art.draw(qp, "holder", model, cx, top, art.HOLDER_H)
            qp.restore()
            return
        if stick > 0:
            cls._stick(qp, model, cx, top, stick)
        art.draw(qp, "holder", model, cx, top, art.HOLDER_H)
        qp.save()
        qp.setOpacity(1 - slide)
        art.draw(qp, "charger", model, cx - 62 * slide, charger_top, art.CHARGER_H)
        qp.restore()

    @staticmethod
    def _stick(qp: QPainter, model: str, cx: float, entry_top: float, k: float) -> None:
        """Stick TEREA a descer até ficar com o filtro de fora (k: 0 longe, 1 encaixado)."""
        final = entry_top - 26
        qp.save()
        qp.setOpacity(min(k * 2.5, 1.0))
        art.draw(qp, "stick", model, cx, final - 30 * (1 - k), art.STICK_H)
        qp.restore()
