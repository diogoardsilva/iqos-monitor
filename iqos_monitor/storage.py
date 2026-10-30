"""Guarda dispositivos e preferências em %APPDATA%\\IqosMonitor\\state.json."""

from __future__ import annotations

import json
import os
from pathlib import Path

from .tracker import DeviceState, Settings


def state_path() -> Path:
    base = os.environ.get("APPDATA") or os.path.join(Path.home(), ".config")
    return Path(base) / "IqosMonitor" / "state.json"


def load(path: Path | None = None) -> Settings:
    path = path or state_path()
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return Settings()
    s = Settings(
        low_battery_pct=int(data.get("low_battery_pct", 20)),
        poll_seconds=int(data.get("poll_seconds", 20)),
        notify_stick_end=bool(data.get("notify_stick_end", True)),
        auto_update=bool(data.get("auto_update", True)),
    )
    s.devices = [DeviceState.from_dict(d) for d in data.get("devices", []) if "address" in d]
    return s


def save(s: Settings, path: Path | None = None) -> None:
    path = path or state_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    data = {
        "low_battery_pct": s.low_battery_pct,
        "poll_seconds": s.poll_seconds,
        "notify_stick_end": s.notify_stick_end,
        "auto_update": s.auto_update,
        "devices": [d.to_dict() for d in s.devices],
    }
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")
    tmp.replace(path)
