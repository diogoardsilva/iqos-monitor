"""Interface Windows (PySide6) com ícone na área de notificação e avisos.

O aspeto segue as Human Interface Guidelines da Apple (ver theme.py).
"""

from __future__ import annotations

import asyncio
import functools
from datetime import datetime
from pathlib import Path

from PySide6.QtCore import QRectF, Qt, QTimer
from PySide6.QtGui import QColor, QFont, QIcon, QPainter, QPixmap
from PySide6.QtWidgets import (
    QApplication, QCheckBox, QDialog, QDialogButtonBox, QFormLayout, QFrame,
    QGraphicsDropShadowEffect, QHBoxLayout, QInputDialog, QLabel, QListWidget, QListWidgetItem,
    QMainWindow, QMenu, QMessageBox, QPushButton, QScrollArea, QSpinBox, QSystemTrayIcon,
    QVBoxLayout, QWidget,
)

from . import storage, theme, updater
from .ble import IqosConnection, SimulatedConnection, scan
from .popup import HolderPopup
from .theme import BatteryRing, font
from .tracker import Alert, DeviceState, Settings
from .version import __version__

ACCENT = "#0f7b8a"


def make_icon(color: str = ACCENT) -> QIcon:
    pm = QPixmap(64, 64)
    pm.fill(Qt.transparent)
    p = QPainter(pm)
    p.setRenderHint(QPainter.Antialiasing)
    p.setBrush(QColor(color))
    p.setPen(Qt.NoPen)
    p.drawRoundedRect(QRectF(4, 4, 56, 56), 14, 14)
    p.setPen(QColor("white"))
    p.setFont(font(22, QFont.Bold))
    p.drawText(pm.rect(), Qt.AlignCenter, "IQ")
    p.end()
    return QIcon(pm)


def secondary(text: str = "", size: float = 9) -> QLabel:
    lbl = QLabel(text)
    lbl.setObjectName("secondary")
    lbl.setFont(font(size))
    return lbl


class Stat(QWidget):
    def __init__(self, caption: str) -> None:
        super().__init__()
        lay = QVBoxLayout(self)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.setSpacing(0)
        self.value = QLabel("—")
        self.value.setFont(font(20, QFont.DemiBold))
        self.value.setAlignment(Qt.AlignCenter)
        cap = secondary(caption)
        cap.setAlignment(Qt.AlignCenter)
        lay.addWidget(self.value)
        lay.addWidget(cap)
        self.caption = caption

    def set(self, text: str) -> None:
        self.value.setText(text)
        self.setAccessibleName(f"{self.caption}: {text}")


class DeviceCard(QFrame):
    def __init__(self, app: "MainWindow", dev: DeviceState) -> None:
        super().__init__()
        self.app, self.dev = app, dev
        self.setObjectName("card")
        shadow = QGraphicsDropShadowEffect(self, blurRadius=18, xOffset=0, yOffset=2)
        shadow.setColor(QColor(0, 0, 0, 28))
        self.setGraphicsEffect(shadow)
        lay = QVBoxLayout(self)
        lay.setContentsMargins(18, 14, 12, 16)
        lay.setSpacing(12)

        head = QHBoxLayout()
        names = QVBoxLayout()
        names.setSpacing(0)
        self.title = QLabel()
        self.title.setFont(font(13, QFont.DemiBold))
        self.subtitle = secondary()
        names.addWidget(self.title)
        names.addWidget(self.subtitle)
        head.addLayout(names)
        head.addStretch()
        self.more = QPushButton("⋯")
        self.more.setObjectName("more")
        self.more.setToolTip("Mais ações")
        self.more.setAccessibleName(f"Mais ações para {dev.alias}")
        self.menu = QMenu(self)
        self.a_conn = self.menu.addAction("", lambda: app.toggle_connection(dev))
        self.menu.addAction("Mudar o nome…", lambda: app.rename(dev))
        self.menu.addAction("Repor contagem", lambda: app.reset_counts(dev))
        self.menu.addSeparator()
        self.menu.addAction("Remover…", lambda: app.remove(dev))
        self.more.setMenu(self.menu)
        head.addWidget(self.more, 0, Qt.AlignTop)
        lay.addLayout(head)

        rings = QHBoxLayout()
        rings.addStretch()
        self.r_charger = BatteryRing("Carregador")
        self.r_holder = BatteryRing("Holder")
        rings.addWidget(self.r_charger)
        rings.addSpacing(16)
        rings.addWidget(self.r_holder)
        rings.addStretch()
        lay.addLayout(rings)

        line = QFrame()
        line.setFixedHeight(1)
        line.setObjectName("separator")
        lay.addWidget(line)

        stats = QHBoxLayout()
        self.s_left = Stat("restam")
        self.s_since = Stat("desde a carga")
        self.s_today = Stat("hoje")
        for s in (self.s_left, self.s_since, self.s_today):
            stats.addWidget(s)
        lay.addLayout(stats)

        self.event = secondary()
        self.event.setWordWrap(True)
        self.event.setAlignment(Qt.AlignCenter)
        lay.addWidget(self.event)
        self.refresh()

    def contextMenuEvent(self, ev) -> None:
        self.menu.exec(ev.globalPos())

    def refresh(self) -> None:
        d = self.dev
        self.title.setText(d.alias)
        dot = "🟢" if d.connected else "⚪"
        self.subtitle.setText(f"{d.model.value} · {dot} {d.status_text}")
        one = d.model.one_piece
        self.r_charger.caption = "Bateria" if one else "Carregador"
        self.r_charger.set_value(d.charger_pct, d.charging, "a carregar" if d.charging else "")
        self.r_holder.setVisible(not one)
        if d.holder_in_charger:
            self.r_holder.set_value(d.holder_pct, (d.holder_pct or 100) < 100, "no carregador")
        elif d.holder_in_charger is False:
            self.r_holder.set_value(None, note="fora do carregador")
        else:
            self.r_holder.set_value(None)
        rem = d.sticks_remaining
        self.s_left.set("—" if rem is None else f"~{rem}")
        self.s_since.set(str(d.sticks_since_charge))
        self.s_today.set(str(d.sticks_today))
        extra = []
        if d.last_event:
            extra.append(d.last_event)
        if d.connected and not d.telemetry_ok:
            extra.append("a contar pelo holder")
        self.event.setText(" · ".join(extra))
        self.event.setVisible(bool(extra))
        self.a_conn.setText("Desligar" if d.address in self.app.conns else "Ligar")
        self.setToolTip(f"{d.pct_per_stick:.1f}% de bateria por cigarro"
                        + (f" · {d.battery_voltage:.2f} V" if d.battery_voltage else ""))


class ScanDialog(QDialog):
    def __init__(self, parent: "MainWindow") -> None:
        super().__init__(parent)
        self.setWindowTitle("Adicionar IQOS")
        self.resize(420, 340)
        lay = QVBoxLayout(self)
        lay.setContentsMargins(20, 18, 20, 18)
        t = QLabel("Adicionar IQOS")
        t.setFont(font(15, QFont.DemiBold))
        lay.addWidget(t)
        self.info = secondary("Ponha o IQOS em modo de emparelhamento. A procura começa sozinha.",
                              10)
        self.info.setWordWrap(True)
        lay.addWidget(self.info)
        self.list = QListWidget()
        lay.addWidget(self.list)
        row = QHBoxLayout()
        self.b_scan = QPushButton("Procurar outra vez")
        self.b_scan.clicked.connect(lambda: asyncio.ensure_future(self.do_scan()))
        row.addWidget(self.b_scan)
        row.addStretch()
        cancel = QPushButton("Cancelar")
        cancel.clicked.connect(self.reject)
        self.ok = QPushButton("Adicionar")
        self.ok.setObjectName("primary")
        self.ok.setDefault(True)
        self.ok.setEnabled(False)
        self.ok.clicked.connect(self.accept)
        row.addWidget(cancel)
        row.addWidget(self.ok)
        lay.addLayout(row)
        self.known = {d.address for d in parent.settings.devices}

    async def do_scan(self) -> None:
        self.b_scan.setEnabled(False)
        self.info.setText("A procurar IQOS por perto…")
        self.list.clear()
        try:
            found = await scan(8)
        except Exception as e:
            self.info.setText(f"O Bluetooth não respondeu ({e}). Confirme que está ligado "
                              "nas Definições do Windows.")
            self.b_scan.setEnabled(True)
            return
        for f in found:
            if f.address in self.known:
                continue
            it = QListWidgetItem(f"{f.name}")
            it.setToolTip(f"{f.address} · sinal {f.rssi} dBm")
            it.setData(Qt.UserRole, (f.address, f.name))
            it.setCheckState(Qt.Checked)
            self.list.addItem(it)
        n = self.list.count()
        self.info.setText(f"{n} IQOS encontrado{'s' if n != 1 else ''}." if n else
                          "Não encontrei nenhum IQOS. Confirme que está em modo de "
                          "emparelhamento e perto do computador.")
        self.ok.setEnabled(n > 0)
        self.b_scan.setEnabled(True)

    def selected(self) -> list[tuple[str, str]]:
        return [self.list.item(i).data(Qt.UserRole) for i in range(self.list.count())
                if self.list.item(i).checkState() == Qt.Checked]


class SettingsDialog(QDialog):
    def __init__(self, parent: "MainWindow") -> None:
        super().__init__(parent)
        self.setWindowTitle("Definições")
        s = parent.settings
        form = QFormLayout(self)
        form.setContentsMargins(20, 18, 20, 18)
        form.setVerticalSpacing(10)
        self.low = QSpinBox()
        self.low.setRange(5, 60)
        self.low.setSuffix(" %")
        self.low.setValue(s.low_battery_pct)
        self.poll = QSpinBox()
        self.poll.setRange(5, 300)
        self.poll.setSuffix(" s")
        self.poll.setValue(s.poll_seconds)
        self.notify = QCheckBox("Avisar quando cada cigarro termina")
        self.notify.setChecked(s.notify_stick_end)
        self.auto = QCheckBox("Instalar atualizações automaticamente")
        self.auto.setChecked(s.auto_update)
        self.popup = QCheckBox("Mostrar janela no canto ao tirar o holder")
        self.popup.setChecked(s.show_popup)
        form.addRow("Avisar bateria fraca abaixo de", self.low)
        form.addRow("Ler o contador a cada", self.poll)
        form.addRow(self.notify)
        form.addRow(self.popup)
        form.addRow(self.auto)
        form.addRow(secondary(f"IQOS Monitor {__version__}"))
        bb = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel)
        bb.button(QDialogButtonBox.Ok).setText("Guardar")
        bb.button(QDialogButtonBox.Ok).setObjectName("primary")
        bb.button(QDialogButtonBox.Cancel).setText("Cancelar")
        bb.accepted.connect(self.accept)
        bb.rejected.connect(self.reject)
        form.addRow(bb)


class MainWindow(QMainWindow):
    def __init__(self, settings: Settings, demo: bool = False,
                 state_file: Path | None = None) -> None:
        super().__init__()
        self.settings, self.demo, self.state_file = settings, demo, state_file
        self.conns: dict[str, IqosConnection] = {}
        self.cards: dict[str, DeviceCard] = {}
        self.quitting = False
        self.setWindowTitle("IQOS Monitor" + (" — simulação" if demo else ""))
        self.setWindowIcon(make_icon())
        self.resize(440, 720)
        self.apply_theme()
        try:
            QApplication.styleHints().colorSchemeChanged.connect(self.apply_theme)
        except AttributeError:
            pass

        root = QWidget()
        root_l = QVBoxLayout(root)
        root_l.setContentsMargins(20, 18, 20, 0)
        root_l.setSpacing(10)
        header = QHBoxLayout()
        title = QLabel("Os meus IQOS")
        title.setFont(font(20, QFont.Bold))
        header.addWidget(title)
        header.addStretch()
        add = QPushButton("＋ Adicionar")
        add.setObjectName("primary")
        add.clicked.connect(self.add_devices)
        header.addWidget(add)
        more = QPushButton("⋯")
        more.setObjectName("more")
        more.setToolTip("Mais")
        more.setAccessibleName("Mais opções")
        app_menu = QMenu(self)
        app_menu.addAction("Definições…", self.edit_settings)
        app_menu.addAction("Procurar atualizações",
                           lambda: asyncio.ensure_future(self.check_updates(manual=True)))
        app_menu.addSeparator()
        app_menu.addAction("Sair", self.quit)
        more.setMenu(app_menu)
        header.addWidget(more)
        root_l.addLayout(header)

        self.list_w = QWidget()
        self.list_w.setObjectName("list")
        self.list_l = QVBoxLayout(self.list_w)
        self.list_l.setContentsMargins(0, 6, 0, 18)
        self.list_l.setSpacing(14)
        self.empty = QWidget()
        el = QVBoxLayout(self.empty)
        e1 = QLabel("Nenhum IQOS ainda")
        e1.setFont(font(15, QFont.DemiBold))
        e2 = secondary("Ligue o Bluetooth, ponha o IQOS em modo de emparelhamento\n"
                       "e carregue em Adicionar.", 10)
        for w in (e1, e2):
            w.setAlignment(Qt.AlignCenter)
            el.addWidget(w)
        self.list_l.addWidget(self.empty)
        self.list_l.addStretch()
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QFrame.NoFrame)
        scroll.setWidget(self.list_w)
        root_l.addWidget(scroll)
        self.setCentralWidget(root)

        self.popup = HolderPopup()
        self.tray = QSystemTrayIcon(make_icon(), self)
        menu = QMenu()
        menu.addAction("Abrir", self.show_normal)
        menu.addAction("Sair", self.quit)
        self.tray.setContextMenu(menu)
        self.tray.activated.connect(
            lambda r: self.show_normal() if r == QSystemTrayIcon.Trigger else None)
        self.tray.show()

        self._save_timer = QTimer(self, singleShot=True, interval=2000, timeout=self.save)
        self._tray_timer = QTimer(self, interval=5000, timeout=self.update_tray_tip)
        self._tray_timer.start()
        self._updating = False
        self._update_timer = QTimer(self, interval=6 * 3600 * 1000,
                                    timeout=lambda: asyncio.ensure_future(self.check_updates()))
        self._update_timer.start()
        if not demo:
            QTimer.singleShot(10_000, lambda: asyncio.ensure_future(self.check_updates()))

        for d in settings.devices:
            self._add_card(d)
            self.connect_device(d)

    def apply_theme(self, *_args) -> None:
        QApplication.instance().setFont(font(10))
        QApplication.instance().setStyleSheet(theme.stylesheet(theme.palette()))
        for c in getattr(self, "cards", {}).values():
            c.refresh()

    # ---- dispositivos ------------------------------------------------------

    def _add_card(self, d: DeviceState) -> None:
        card = DeviceCard(self, d)
        self.cards[d.address] = card
        self.list_l.insertWidget(self.list_l.count() - 1, card)
        self.empty.hide()

    def connect_device(self, d: DeviceState) -> None:
        cls = SimulatedConnection if self.demo else IqosConnection
        conn = cls(d.address,
                   on_battery=functools.partial(self._on_battery, d),
                   on_telemetry=functools.partial(self._on_telemetry, d),
                   on_status=functools.partial(self._on_status, d),
                   poll_seconds=self.settings.poll_seconds)
        self.conns[d.address] = conn
        conn.start()
        self.refresh(d)

    def toggle_connection(self, d: DeviceState) -> None:
        conn = self.conns.pop(d.address, None)
        if conn:
            asyncio.ensure_future(conn.stop())
            self.refresh(d)
        else:
            self.connect_device(d)

    def add_devices(self) -> None:
        if self.demo:
            n = len(self.settings.devices) + 1
            self._new_device(f"SIM-{n:02d}", f"IQOS ILUMA i (simulado {n})")
            return
        dlg = ScanDialog(self)
        asyncio.ensure_future(dlg.do_scan())
        if dlg.exec() == QDialog.Accepted:
            for addr, name in dlg.selected():
                self._new_device(addr, name)

    def _new_device(self, address: str, name: str) -> None:
        d = DeviceState(address=address, name=name)
        self.settings.devices.append(d)
        self._add_card(d)
        self.connect_device(d)
        self.schedule_save()

    def rename(self, d: DeviceState) -> None:
        name, ok = QInputDialog.getText(self, "Renomear", "Nome:", text=d.alias)
        if ok and name.strip():
            d.alias = name.strip()
            self.refresh(d)
            self.schedule_save()

    def reset_counts(self, d: DeviceState) -> None:
        d.sticks_today = 0
        d.sticks_since_charge = 0
        self.refresh(d)
        self.schedule_save()

    def remove(self, d: DeviceState) -> None:
        box = QMessageBox(QMessageBox.Warning, f"Remover {d.alias}?",
                          f"Remover {d.alias}?", parent=self)
        box.setInformativeText("A contagem guardada deste IQOS é apagada.")
        rm = box.addButton("Remover", QMessageBox.DestructiveRole)
        box.addButton("Cancelar", QMessageBox.RejectRole)
        box.exec()
        if box.clickedButton() is not rm:
            return
        conn = self.conns.pop(d.address, None)
        if conn:
            asyncio.ensure_future(conn.stop())
        self.settings.devices.remove(d)
        self.cards.pop(d.address).deleteLater()
        self.empty.setVisible(not self.settings.devices)
        self.schedule_save()

    def edit_settings(self) -> None:
        dlg = SettingsDialog(self)
        if dlg.exec() == QDialog.Accepted:
            self.settings.low_battery_pct = dlg.low.value()
            self.settings.poll_seconds = dlg.poll.value()
            self.settings.notify_stick_end = dlg.notify.isChecked()
            self.settings.auto_update = dlg.auto.isChecked()
            self.settings.show_popup = dlg.popup.isChecked()
            for c in self.conns.values():
                c.poll_seconds = self.settings.poll_seconds
            self.schedule_save()

    # ---- callbacks BLE -----------------------------------------------------

    def _on_battery(self, d: DeviceState, b) -> None:
        self._handle(d, d.on_battery(b, datetime.now(), self.settings.low_battery_pct))

    def _on_telemetry(self, d: DeviceState, t) -> None:
        self._handle(d, d.on_telemetry(t, datetime.now(), self.settings.low_battery_pct))

    def _on_status(self, d: DeviceState, connected: bool, text: str) -> None:
        # Nos ONE não há holder: o IQOS liga-se quando é ativado, mostra a janela aí.
        if connected and not d.connected and d.model.one_piece and self.settings.show_popup:
            QTimer.singleShot(1500, lambda: self.popup.show_for(d, leaving=True))
        d.connected, d.status_text = connected, text
        self.refresh(d)

    def _handle(self, d: DeviceState, alerts: list[Alert]) -> None:
        for a in alerts:
            if a.kind in ("holder_out", "holder_in"):
                if self.settings.show_popup:
                    self.popup.show_for(d, leaving=a.kind == "holder_out")
                continue
            if a.kind == "stick_end" and not self.settings.notify_stick_end:
                continue
            self.notify(a)
        self.refresh(d)
        self.schedule_save()

    def notify(self, a: Alert) -> None:
        icon = (QSystemTrayIcon.Warning if a.kind in ("low_battery", "holder_charge")
                else QSystemTrayIcon.Information)
        self.tray.showMessage(a.title, a.message, icon, 8000)
        QApplication.beep()

    # ---- atualizações -----------------------------------------------------

    async def check_updates(self, manual: bool = False) -> None:
        if self._updating:
            return
        self._updating = True
        try:
            rel = await asyncio.to_thread(updater.check_latest)
            if rel is None:
                if manual:
                    QMessageBox.information(self, "Atualizações",
                                            f"Já tem a versão mais recente ({__version__}).")
                return
            if not updater.can_self_update():
                if manual:
                    QMessageBox.information(self, "Atualizações",
                                            f"Há uma versão nova ({rel.version}):\n{rel.page_url}")
                return
            if not (self.settings.auto_update or manual):
                self.tray.showMessage("Atualização disponível",
                                      f"Versão {rel.version}. Use “Procurar atualizações”.",
                                      QSystemTrayIcon.Information, 8000)
                return
            if manual and QMessageBox.question(
                    self, "Atualizar", f"Instalar a versão {rel.version} e reiniciar?\n\n"
                    f"{rel.notes[:600]}") != QMessageBox.Yes:
                return
            new_exe = await asyncio.to_thread(updater.download, rel)
            for c in list(self.conns.values()):
                await c.stop()  # liberta o Bluetooth antes de reiniciar
            self.save()
            updater.install_and_restart(new_exe)
            self.quit()
        except Exception as e:
            if manual:
                QMessageBox.warning(self, "Atualizações", f"Não foi possível atualizar: {e}")
        finally:
            self._updating = False

    # ---- diversos ----------------------------------------------------------

    def refresh(self, d: DeviceState) -> None:
        card = self.cards.get(d.address)
        if card:
            card.refresh()

    def update_tray_tip(self) -> None:
        lines = []
        for d in self.settings.devices:
            pct = "—" if d.charger_pct is None else f"{d.charger_pct}%"
            rem = d.sticks_remaining
            lines.append(f"{d.alias}: {pct}, ~{rem if rem is not None else '?'} cigarros")
        self.tray.setToolTip("\n".join(lines) or "IQOS Monitor")

    def schedule_save(self) -> None:
        self._save_timer.start()

    def save(self) -> None:
        storage.save(self.settings, self.state_file)

    def show_normal(self) -> None:
        self.show()
        self.setWindowState(self.windowState() & ~Qt.WindowMinimized)
        self.raise_()
        self.activateWindow()

    def closeEvent(self, ev) -> None:
        if self.quitting or not QSystemTrayIcon.isSystemTrayAvailable():
            self.save()
            ev.accept()
            return
        ev.ignore()
        self.hide()
        self.tray.showMessage("IQOS Monitor", "Continua a vigiar em segundo plano.",
                              QSystemTrayIcon.Information, 3000)

    def quit(self) -> None:
        self.quitting = True
        self.save()
        QApplication.quit()
