"""Aspeto inspirado nas Human Interface Guidelines da Apple.

Cores semânticas com variantes clara e escura (segue o tema do Windows),
fonte do sistema com hierarquia de estilos de texto, e um anel de bateria
no estilo do widget Baterias.
"""

from __future__ import annotations

from dataclasses import dataclass

from PySide6.QtCore import QRectF, Qt
from PySide6.QtGui import QColor, QFont, QGuiApplication, QPainter, QPen
from PySide6.QtWidgets import QWidget


@dataclass(frozen=True)
class Palette:
    background: str  # fundo da janela (grouped background)
    card: str  # fundo dos cartões (secondary grouped)
    fill: str  # pista dos anéis e botões secundários
    label: str
    secondary: str
    separator: str
    accent: str
    green: str
    orange: str
    red: str


# Valores de referência das cores de sistema da Apple (claro / escuro).
LIGHT = Palette("#F2F2F7", "#FFFFFF", "#E5E5EA", "#1C1C1E", "#6E6E73", "#D1D1D6",
                "#007AFF", "#248A3D", "#C93400", "#D70015")
DARK = Palette("#000000", "#1C1C1E", "#2C2C2E", "#F5F5F7", "#98989F", "#38383A",
               "#0A84FF", "#30D158", "#FF9F0A", "#FF453A")


FORCE_DARK: bool | None = None  # None = seguir o Windows


def is_dark() -> bool:
    if FORCE_DARK is not None:
        return FORCE_DARK
    try:
        return QGuiApplication.styleHints().colorScheme() == Qt.ColorScheme.Dark
    except AttributeError:  # Qt < 6.5
        return False


def palette() -> Palette:
    return DARK if is_dark() else LIGHT


def font(size: float, weight: QFont.Weight = QFont.Normal) -> QFont:
    f = QFont()
    f.setFamilies(["Segoe UI Variable Display", "Segoe UI", "Inter"])
    f.setPointSizeF(size)
    f.setWeight(weight)
    return f


def battery_color(p: Palette, pct: int | None) -> str:
    if pct is None:
        return p.secondary
    return p.red if pct <= 20 else p.orange if pct <= 40 else p.green


def stylesheet(p: Palette) -> str:
    return f"""
    QMainWindow, QDialog {{ background: {p.background}; }}
    QWidget {{ color: {p.label}; }}
    QScrollArea, #list {{ background: transparent; border: none; }}
    #card {{ background: {p.card}; border-radius: 14px; }}
    #secondary {{ color: {p.secondary}; }}
    #separator {{ background: {p.separator}; }}
    QPushButton {{
        background: {p.fill}; border: none; border-radius: 8px;
        padding: 6px 14px; font-weight: 500;
    }}
    QPushButton:hover {{ background: {p.separator}; }}
    QPushButton#primary {{ background: {p.accent}; color: white; }}
    QPushButton#primary:hover {{ background: {p.accent}; }}
    QPushButton#more {{
        background: transparent; color: {p.accent}; font-size: 16pt;
        padding: 0 8px; border-radius: 15px; min-width: 30px; min-height: 30px;
    }}
    QPushButton#more:hover {{ background: {p.fill}; }}
    QPushButton#more::menu-indicator {{ image: none; width: 0; }}
    QMenu {{ background: {p.card}; border: 1px solid {p.separator}; border-radius: 8px;
             padding: 4px; }}
    QMenu::item {{ padding: 6px 18px; border-radius: 5px; }}
    QMenu::item:selected {{ background: {p.accent}; color: white; }}
    QMenu::separator {{ height: 1px; background: {p.separator}; margin: 4px 8px; }}
    QListWidget, QSpinBox, QLineEdit {{
        background: {p.card}; border: 1px solid {p.separator}; border-radius: 8px; padding: 4px;
    }}
    """


class BatteryRing(QWidget):
    """Anel de capacidade com a percentagem ao centro e uma legenda por baixo."""

    def __init__(self, caption: str, size: int = 84) -> None:
        super().__init__()
        self.caption = caption
        self.pct: int | None = None
        self.charging = False
        self.note = ""
        self._size = size
        self.setFixedSize(size + 40, size + 38)

    def set_value(self, pct: int | None, charging: bool = False, note: str = "") -> None:
        self.pct, self.charging, self.note = pct, charging, note
        value = "sem leitura" if pct is None else f"{pct} por cento"
        self.setAccessibleName(f"{self.caption}: {value}{', ' + note if note else ''}")
        self.update()

    def paintEvent(self, _ev) -> None:
        p = palette()
        qp = QPainter(self)
        qp.setRenderHint(QPainter.Antialiasing)
        s, w = self._size, 8
        rect = QRectF((self.width() - s) / 2 + w / 2, w / 2, s - w, s - w)
        qp.setPen(QPen(QColor(p.fill), w, Qt.SolidLine, Qt.RoundCap))
        qp.drawEllipse(rect)
        if self.pct:
            qp.setPen(QPen(QColor(battery_color(p, self.pct)), w, Qt.SolidLine, Qt.RoundCap))
            qp.drawArc(rect, 90 * 16, -int(360 * 16 * self.pct / 100))
        qp.setPen(QColor(p.label if self.pct is not None else p.secondary))
        qp.setFont(font(15 if self.pct is not None else 11, QFont.DemiBold))
        center = "—" if self.pct is None else f"{self.pct}%"
        if self.charging and self.pct is not None:
            center = f"⚡{self.pct}%"
        qp.drawText(rect, Qt.AlignCenter, center)
        qp.setFont(font(9, QFont.DemiBold))
        qp.setPen(QColor(p.label))
        cap = QRectF(0, s + 2, self.width(), 16)
        qp.drawText(cap, Qt.AlignHCenter | Qt.AlignTop, self.caption)
        if self.note:
            qp.setFont(font(8))
            qp.setPen(QColor(p.secondary))
            qp.drawText(QRectF(0, s + 18, self.width(), 16), Qt.AlignHCenter | Qt.AlignTop,
                        self.note)
        qp.end()
