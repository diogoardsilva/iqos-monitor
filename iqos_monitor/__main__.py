"""Arranque: python -m iqos_monitor [--demo]"""

from __future__ import annotations

import argparse
import asyncio
import logging
import sys
from pathlib import Path

from PySide6.QtCore import QTimer
from PySide6.QtWidgets import QApplication
import qasync

from . import storage, updater
from .gui import MainWindow
from .tracker import DeviceState


def main() -> int:
    ap = argparse.ArgumentParser(prog="IqosMonitor")
    ap.add_argument("--demo", action="store_true", help="usar IQOS simulados")
    ap.add_argument("--updated", action="store_true", help=argparse.SUPPRESS)
    ap.add_argument("--screenshot", type=Path, help=argparse.SUPPRESS)
    ap.add_argument("--after", type=float, default=8, help=argparse.SUPPRESS)
    args = ap.parse_args()

    log_file = storage.state_path().with_name("iqos-monitor.log")
    log_file.parent.mkdir(parents=True, exist_ok=True)
    logging.basicConfig(filename=log_file, level=logging.INFO,
                        format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    updater.cleanup_old()

    app = QApplication(sys.argv)
    app.setApplicationName("IQOS Monitor")
    app.setQuitOnLastWindowClosed(False)
    loop = qasync.QEventLoop(app)
    asyncio.set_event_loop(loop)

    state_file = storage.state_path().with_name("demo.json") if args.demo else None
    settings = storage.load(state_file)
    if args.demo and not settings.devices:
        settings.devices = [DeviceState("SIM-01", "IQOS ILUMA i PRIME", alias="IQOS de casa"),
                            DeviceState("SIM-02", "IQOS ILUMA i ONE", alias="IQOS do carro")]
    win = MainWindow(settings, demo=args.demo, state_file=state_file)
    win.show()
    if args.updated:
        from .version import __version__
        win.tray.showMessage("IQOS Monitor", f"Atualizado para a versão {__version__}.")

    if args.screenshot:
        def shot() -> None:
            win.grab().save(str(args.screenshot))
            win.quit()
        QTimer.singleShot(int(args.after * 1000), shot)

    with loop:
        loop.run_until_complete(app_close_event(app))
    return 0


async def app_close_event(app: QApplication) -> None:
    done = asyncio.Event()
    app.aboutToQuit.connect(done.set)
    await done.wait()


if __name__ == "__main__":
    sys.exit(main())
