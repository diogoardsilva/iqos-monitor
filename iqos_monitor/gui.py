"""Interface Windows (PySide6) com ícone na barra de tarefas e notificações."""

from __future__ import annotations

import asyncio
import functools
from datetime import datetime
from pathlib import Path

from PySide6.QtCore import QRectF, Qt, QTimer
from PySide6.QtGui import QAction, QColor, QFont, QIcon, QPainter, QPixmap
from PySide6.QtWidgets import (
    QApplication, QCheckBox, QDialog, QDialogButtonBox, QFormLayout, QFrame, QGridLayout,
    QHBoxLayout, QInputDialog, QLabel, QListWidget, QListWidgetItem, QMainWindow,
    QMessageBox, QProgressBar, QPushButton, QScrollArea, QSpinBox, QSystemTrayIcon,
    QVBoxLayout, QWidget, QMenu,
)

from . import storage, updater
from .ble import IqosConnection, SimulatedConnection, scan
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
    f = QFont("Segoe UI", 22)
    f.setBold(True)
    p.setFont(f)
    p.drawText(pm.rect(), Qt.AlignCenter, "IQ")
    p.end()
    return QIcon(pm)


def battery_bar() -> QProgressBar:
    bar = QProgressBar()
    bar.setRange(0, 100)
    bar.setTextVisible(True)
    bar.setFixedHeight(18)
    return bar


def set_bar(bar: QProgressBar, pct: int | None, fmt: str = "%p%") -> None:
    if pct is None:
        bar.setValue(0)
        bar.setFormat("—")
        color = "#9aa0a6"
    else:
        bar.setValue(pct)
        bar.setFormat(fmt)
        color = "#d93025" if pct <= 20 else "#f29900" if pct <= 40 else "#1e8e3e"
    bar.setStyleSheet(
        "QProgressBar{border:1px solid #c8ccd0;border-radius:4px;text-align:center;}"
        f"QProgressBar::chunk{{background:{color};border-radius:3px;}}"
    )


class Stat(QWidget):
    def __init__(self, caption: str) -> None:
        super().__init__()
        lay = QVBoxLayout(self)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.setSpacing(0)
        self.value = QLabel("—")
        f = self.value.font()
        f.setPointSize(20)
        f.setBold(True)
        self.value.setFont(f)
        self.value.setAlignment(Qt.AlignCenter)
        cap = QLabel(caption)
        cap.setAlignment(Qt.AlignCenter)
        cap.setStyleSheet("color:#5f6368;")
        lay.addWidget(self.value)
        lay.addWidget(cap)


class DeviceCard(QFrame):
    def __init__(self, app: "MainWindow", dev: DeviceState) -> None:
        super().__init__()
        self.app, self.dev = app, dev
        self.setObjectName("card")
        self.setStyleSheet("#card{background:palette(base);border:1px solid #d0d4d8;"
                           "border-radius:10px;}")
        lay = QVBoxLayout(self)

        head = QHBoxLayout()
        self.dot = QLabel("●")
        self.title = QLabel()
        f = self.title.font()
        f.setPointSize(13)
        f.setBold(True)
        self.title.setFont(f)
        self.model = QLabel()
        self.model.setStyleSheet("color:#5f6368;")
        head.addWidget(self.dot)
        head.addWidget(self.title)
        head.addWidget(self.model)
        head.addStretch()
        self.status = QLabel()
        self.status.setStyleSheet("color:#5f6368;")
        head.addWidget(self.status)
        lay.addLayout(head)

        grid = QGridLayout()
        self.charger_lbl = QLabel("Carregador")
        self.charger_bar = battery_bar()
        self.holder_lbl = QLabel("Holder")
        self.holder_bar = battery_bar()
        grid.addWidget(self.charger_lbl, 0, 0)
        grid.addWidget(self.charger_bar, 0, 1)
        grid.addWidget(self.holder_lbl, 1, 0)
        grid.addWidget(self.holder_bar, 1, 1)
        grid.setColumnStretch(1, 1)
        lay.addLayout(grid)

        stats = QHBoxLayout()
        self.s_today = Stat("hoje")
        self.s_since = Stat("desde a última carga")
        self.s_left = Stat("restam (estimativa)")
        for s in (self.s_today, self.s_since, self.s_left):
            stats.addWidget(s)
        lay.addLayout(stats)

        self.event = QLabel()
        self.event.setStyleSheet("color:#5f6368;")
        lay.addWidget(self.event)

        btns = QHBoxLayout()
        self.b_conn = QPushButton()
        self.b_conn.clicked.connect(lambda: app.toggle_connection(dev))
        b_ren = QPushButton("Renomear")
        b_ren.clicked.connect(lambda: app.rename(dev))
        b_reset = QPushButton("Repor contagem")
        b_reset.clicked.connect(lambda: app.reset_counts(dev))
        b_rm = QPushButton("Remover")
        b_rm.clicked.connect(lambda: app.remove(dev))
        for b in (self.b_conn, b_ren, b_reset, b_rm):
            btns.addWidget(b)
        btns.addStretch()
        lay.addLayout(btns)
        self.refresh()

    def refresh(self) -> None:
        d = self.dev
        self.title.setText(d.alias)
        self.model.setText(d.model.value)
        self.dot.setStyleSheet(f"color:{'#1e8e3e' if d.connected else '#9aa0a6'};font-size:16px;")
        self.status.setText(d.status_text)
        one = d.model.one_piece
        self.charger_lbl.setText("Bateria" if one else "Carregador")
        set_bar(self.charger_bar, d.charger_pct)
        self.holder_lbl.setVisible(not one)
        self.holder_bar.setVisible(not one)
        if d.holder_in_charger:
            set_bar(self.holder_bar, d.holder_pct, "%p% (no carregador)")
        elif d.holder_in_charger is False:
            set_bar(self.holder_bar, None)
            self.holder_bar.setFormat("fora do carregador")
        else:
            set_bar(self.holder_bar, None)
        self.s_today.value.setText(str(d.sticks_today))
        self.s_since.value.setText(str(d.sticks_since_charge))
        rem = d.sticks_remaining
        self.s_left.value.setText("—" if rem is None else f"~{rem}")
        extra = []
        if d.last_event:
            extra.append(d.last_event)
        if d.connected and not d.telemetry_ok:
            extra.append("contador do dispositivo indisponível: a contar pelo holder")
        if d.battery_voltage:
            extra.append(f"{d.battery_voltage:.2f} V")
        extra.append(f"{d.pct_per_stick:.1f}% por cigarro")
        self.event.setText(" · ".join(extra))
        self.b_conn.setText("Desligar" if d.address in self.app.conns else "Ligar")


class ScanDialog(QDialog):
    def __init__(self, parent: "MainWindow") -> None:
        super().__init__(parent)
        self.setWindowTitle("Adicionar IQOS")
        self.resize(420, 320)
        lay = QVBoxLayout(self)
        self.info = QLabel("Ponha o IQOS em modo de emparelhamento e carregue em Procurar.")
        self.info.setWordWrap(True)
        lay.addWidget(self.info)
        self.list = QListWidget()
        lay.addWidget(self.list)
        self.b_scan = QPushButton("Procurar")
        self.b_scan.clicked.connect(lambda: asyncio.ensure_future(self.do_scan()))
        lay.addWidget(self.b_scan)
        bb = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel)
        bb.button(QDialogButtonBox.Ok).setText("Adicionar selecionados")
        bb.accepted.connect(self.accept)
        bb.rejected.connect(self.reject)
        lay.addWidget(bb)
        self.known = {d.address for d in parent.settings.devices}

    async def do_scan(self) -> None:
        self.b_scan.setEnabled(False)
        self.info.setText("A procurar durante 8 segundos…")
        self.list.clear()
        try:
            found = await scan(8)
        except Exception as e:
            self.info.setText(f"Erro no Bluetooth: {e}. Confirme que está ligado no Windows.")
            self.b_scan.setEnabled(True)
            return
        for f in found:
            if f.address in self.known:
                continue
            it = QListWidgetItem(f"{f.name}  ({f.address}, {f.rssi} dBm)")
            it.setData(Qt.UserRole, (f.address, f.name))
            it.setCheckState(Qt.Checked)
            self.list.addItem(it)
        self.info.setText(f"Encontrados {self.list.count()} IQOS novos." if self.list.count()
                          else "Nenhum IQOS encontrado. Confirme o modo de emparelhamento.")
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
        form.addRow("Avisar bateria fraca abaixo de", self.low)
        form.addRow("Ler o contador a cada", self.poll)
        self.auto = QCheckBox("Instalar atualizações automaticamente")
        self.auto.setChecked(s.auto_update)
        form.addRow(self.notify)
        form.addRow(self.auto)
        bb = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel)
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
        self.setWindowTitle(f"IQOS Monitor {__version__}" + (" — simulação" if demo else ""))
        self.setWindowIcon(make_icon())
        self.resize(560, 640)

        tb = self.addToolBar("main")
        tb.setMovable(False)
        a_add = QAction("Adicionar IQOS", self)
        a_add.triggered.connect(self.add_devices)
        a_set = QAction("Definições", self)
        a_set.triggered.connect(self.edit_settings)
        a_upd = QAction("Procurar atualizações", self)
        a_upd.triggered.connect(lambda: asyncio.ensure_future(self.check_updates(manual=True)))
        tb.addAction(a_add)
        tb.addAction(a_set)
        tb.addAction(a_upd)

        self.list_w = QWidget()
        self.list_l = QVBoxLayout(self.list_w)
        self.list_l.setSpacing(12)
        self.empty = QLabel("Ainda não há nenhum IQOS.\nCarregue em “Adicionar IQOS”.")
        self.empty.setAlignment(Qt.AlignCenter)
        self.empty.setStyleSheet("color:#5f6368;font-size:14px;")
        self.list_l.addWidget(self.empty)
        self.list_l.addStretch()
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setWidget(self.list_w)
        self.setCentralWidget(scroll)

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
        if QMessageBox.question(self, "Remover", f"Remover {d.alias}?") != QMessageBox.Yes:
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
            for c in self.conns.values():
                c.poll_seconds = self.settings.poll_seconds
            self.schedule_save()

    # ---- callbacks BLE -----------------------------------------------------

    def _on_battery(self, d: DeviceState, b) -> None:
        self._handle(d, d.on_battery(b, datetime.now(), self.settings.low_battery_pct))

    def _on_telemetry(self, d: DeviceState, t) -> None:
        self._handle(d, d.on_telemetry(t, datetime.now(), self.settings.low_battery_pct))

    def _on_status(self, d: DeviceState, connected: bool, text: str) -> None:
        d.connected, d.status_text = connected, text
        self.refresh(d)

    def _handle(self, d: DeviceState, alerts: list[Alert]) -> None:
        for a in alerts:
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
