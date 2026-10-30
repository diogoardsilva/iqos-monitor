"""Ilustrações vetoriais dos aparelhos (SVG desenhado à mão, sem logótipos).

Proporções aproximadas dos aparelhos reais (mm): carregador ILUMA 46×98,
holder 15×100, ILUMA ONE 32×117, stick TEREA 7×45. As cores seguem as
cores de série de cada modelo. Qt SVG não suporta filtros, por isso
sombras e brilhos são feitos só com gradientes.
"""

from __future__ import annotations

from dataclasses import dataclass
from functools import lru_cache

from PySide6.QtCore import QByteArray, QRectF
from PySide6.QtGui import QPainter
from PySide6.QtSvg import QSvgRenderer


@dataclass(frozen=True)
class Finish:
    base: str
    light: str
    dark: str
    wrap: str = ""  # capa envolvente dos PRIME
    led: str = "#FFFFFF"


FINISHES = {
    "ILUMA": Finish("#A9ABAE", "#E4E5E7", "#5E6064"),  # Pebble Grey
    "ILUMA PRIME": Finish("#3C3E42", "#7A7D82", "#141517", wrap="#26272A"),  # Obsidian
    "ILUMA i": Finish("#7FA3BF", "#C9DCEA", "#3F5D74"),  # Breeze Blue
    "ILUMA i PRIME": Finish("#3F6157", "#86A79C", "#1C2E28", wrap="#2C463E"),  # Jade
    "ILUMA ONE": Finish("#4F7FA3", "#A9C8DF", "#233F55"),  # Azure Blue
    "ILUMA i ONE": Finish("#A9ABAE", "#E4E5E7", "#5E6064"),
}


def finish_for(model: str) -> Finish:
    return FINISHES.get(model, FINISHES["ILUMA"])


def _cyl(id_: str, f: Finish) -> str:
    """Gradiente horizontal de um corpo arredondado iluminado da esquerda."""
    return f"""
    <linearGradient id="{id_}" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="{f.dark}"/>
      <stop offset="0.10" stop-color="{f.base}"/>
      <stop offset="0.30" stop-color="{f.light}"/>
      <stop offset="0.42" stop-color="{f.base}"/>
      <stop offset="0.86" stop-color="{f.base}"/>
      <stop offset="1" stop-color="{f.dark}"/>
    </linearGradient>"""


SHADE = """
    <linearGradient id="shade" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.22"/>
      <stop offset="0.25" stop-color="#FFFFFF" stop-opacity="0"/>
      <stop offset="0.75" stop-color="#000000" stop-opacity="0"/>
      <stop offset="1" stop-color="#000000" stop-opacity="0.28"/>
    </linearGradient>
    <radialGradient id="ground" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="#000000" stop-opacity="0.35"/>
      <stop offset="1" stop-color="#000000" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="hole" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#050505"/>
      <stop offset="1" stop-color="#2A2A2C"/>
    </linearGradient>"""


def charger_svg(f: Finish) -> str:
    wrap = defs_wrap = ""
    if f.wrap:
        defs_wrap = _cyl("wrap", Finish(f.wrap, f.base, "#0A0A0A"))
        wrap = """
  <rect x="2" y="100" width="96" height="104" rx="30" fill="url(#wrap)"/>
  <rect x="2" y="100" width="96" height="30" fill="url(#wrap)"/>
  <rect x="2" y="100" width="96" height="104" rx="30" fill="url(#shade)"/>
  <rect x="2" y="100" width="96" height="1.2" fill="#000000" fill-opacity="0.35"/>
  <line x1="7" y1="105" x2="93" y2="105" stroke="#FFFFFF" stroke-opacity="0.22"
        stroke-width="0.8" stroke-dasharray="2.5,2"/>"""
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 214">
  <defs>{_cyl("body", f)}{defs_wrap}{SHADE}</defs>
  <ellipse cx="50" cy="206" rx="46" ry="6" fill="url(#ground)"/>
  <rect x="4" y="6" width="92" height="198" rx="30" fill="url(#body)"/>
  <rect x="4" y="6" width="92" height="198" rx="30" fill="url(#shade)"/>
  <rect x="4.6" y="6.6" width="90.8" height="196.8" rx="29.4" fill="none"
        stroke="#FFFFFF" stroke-opacity="0.35" stroke-width="0.9"/>
  <ellipse cx="50" cy="13" rx="34" ry="4" fill="#FFFFFF" fill-opacity="0.18"/>
  <rect x="32" y="9" width="36" height="12" rx="6" fill="url(#hole)"/>
  <rect x="33" y="18.5" width="34" height="1" rx="0.5" fill="#FFFFFF" fill-opacity="0.18"/>
  {wrap}
  <rect x="45" y="186" width="10" height="2.6" rx="1.3" fill="{f.led}" fill-opacity="0.8"/>
</svg>"""


def holder_svg(f: Finish) -> str:
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 30 200">
  <defs>{_cyl("body", f)}{SHADE}
    <linearGradient id="cap" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="#4A4A4D"/><stop offset="0.3" stop-color="#E9E9EC"/>
      <stop offset="0.45" stop-color="#B8B8BD"/><stop offset="1" stop-color="#3E3E42"/>
    </linearGradient>
  </defs>
  <rect x="3" y="0" width="24" height="200" rx="12" fill="url(#body)"/>
  <rect x="3" y="0" width="24" height="200" rx="12" fill="url(#shade)"/>
  <rect x="3" y="0" width="24" height="34" rx="12" fill="url(#cap)"/>
  <rect x="3" y="22" width="24" height="12" fill="url(#cap)"/>
  <rect x="3" y="33.5" width="24" height="1.4" fill="#000000" fill-opacity="0.45"/>
  <rect x="3" y="35" width="24" height="0.8" fill="#FFFFFF" fill-opacity="0.35"/>
  <ellipse cx="15" cy="5" rx="7.5" ry="3.2" fill="url(#hole)"/>
  <ellipse cx="15" cy="4.2" rx="4.2" ry="1.6" fill="#000000"/>
  <rect x="13.6" y="48" width="2.8" height="26" rx="1.4" fill="{f.led}" fill-opacity="0.55"/>
  <rect x="3.6" y="2" width="1.2" height="190" rx="0.6" fill="#FFFFFF" fill-opacity="0.18"/>
</svg>"""


def one_svg(f: Finish) -> str:
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 246">
  <defs>{_cyl("body", f)}{SHADE}
    <linearGradient id="cap" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="{f.dark}"/><stop offset="0.3" stop-color="{f.light}"/>
      <stop offset="0.5" stop-color="{f.base}"/><stop offset="1" stop-color="{f.dark}"/>
    </linearGradient>
  </defs>
  <ellipse cx="32" cy="240" rx="30" ry="5" fill="url(#ground)"/>
  <rect x="2" y="0" width="60" height="236" rx="26" fill="url(#body)"/>
  <rect x="2" y="0" width="60" height="236" rx="26" fill="url(#shade)"/>
  <rect x="2" y="0" width="60" height="62" rx="26" fill="url(#cap)"/>
  <rect x="2" y="40" width="60" height="22" fill="url(#cap)"/>
  <rect x="2" y="61.5" width="60" height="1.6" fill="#000000" fill-opacity="0.4"/>
  <rect x="2" y="63.1" width="60" height="0.9" fill="#FFFFFF" fill-opacity="0.3"/>
  <ellipse cx="32" cy="9" rx="10" ry="4" fill="url(#hole)"/>
  <ellipse cx="32" cy="8.2" rx="5.5" ry="2" fill="#000000"/>
  <rect x="2.6" y="0.6" width="58.8" height="234.8" rx="25.4" fill="none"
        stroke="#FFFFFF" stroke-opacity="0.3" stroke-width="0.9"/>
  <circle cx="32" cy="92" r="2" fill="{f.led}" fill-opacity="0.85"/>
  <circle cx="32" cy="100" r="2" fill="{f.led}" fill-opacity="0.85"/>
  <circle cx="32" cy="108" r="2" fill="{f.led}" fill-opacity="0.35"/>
</svg>"""


def stick_svg() -> str:
    return """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 14 90">
  <defs>
    <linearGradient id="paper" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="#BDB7AA"/><stop offset="0.3" stop-color="#FFFFFF"/>
      <stop offset="0.6" stop-color="#F1ECE2"/><stop offset="1" stop-color="#A9A396"/>
    </linearGradient>
    <linearGradient id="band" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="#7A2A1A"/><stop offset="0.3" stop-color="#D2643F"/>
      <stop offset="1" stop-color="#6E2416"/>
    </linearGradient>
  </defs>
  <rect x="1" y="1" width="12" height="88" rx="1.5" fill="url(#paper)"/>
  <rect x="1" y="26" width="12" height="5" fill="url(#band)"/>
  <rect x="1" y="34" width="12" height="0.6" fill="#000000" fill-opacity="0.12"/>
  <ellipse cx="7" cy="1.8" rx="5.6" ry="1.6" fill="#E9E3D6"/>
  <ellipse cx="7" cy="1.8" rx="2.4" ry="0.8" fill="#BFB49C"/>
</svg>"""


@lru_cache(maxsize=None)
def renderer(kind: str, model: str = "") -> QSvgRenderer:
    f = finish_for(model)
    svg = {"charger": charger_svg, "holder": holder_svg, "one": one_svg}.get(kind)
    data = svg(f) if svg else stick_svg()
    return QSvgRenderer(QByteArray(data.encode()))


# Altura (px) de cada peça na janela, à mesma escala (~1.2 px/mm).
CHARGER_H, HOLDER_H, ONE_H, STICK_H = 120.0, 114.0, 132.0, 52.0


def draw(qp: QPainter, kind: str, model: str, x_center: float, top: float,
         height: float) -> QRectF:
    r = renderer(kind, model)
    vb = r.viewBoxF()
    w = height * vb.width() / vb.height()
    rect = QRectF(x_center - w / 2, top, w, height)
    r.render(qp, rect)
    return rect
