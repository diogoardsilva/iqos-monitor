"""Atualizações automáticas a partir das releases do GitHub.

Cada release (tag vX.Y.Z) tem dois ficheiros: IqosMonitor.exe e
IqosMonitor.exe.sha256. A app descarrega o .exe novo, confirma o SHA-256,
renomeia o executável em uso para .old (o Windows permite renomear um .exe
aberto), põe o novo no lugar e reinicia.
"""

from __future__ import annotations

import hashlib
import json
import logging
import os
import shutil
import subprocess
import sys
import tempfile
import urllib.request
from dataclasses import dataclass
from pathlib import Path

from .version import GITHUB_REPO, __version__

log = logging.getLogger(__name__)

ASSET_NAME = "IqosMonitor.exe"
USER_AGENT = f"IqosMonitor/{__version__}"


@dataclass
class Release:
    version: str
    notes: str
    exe_url: str
    sha256_url: str | None
    page_url: str


def parse_version(v: str) -> tuple[int, ...]:
    parts = []
    for p in v.strip().lstrip("vV").split("."):
        digits = "".join(ch for ch in p if ch.isdigit())
        parts.append(int(digits or 0))
    return tuple(parts)


def is_newer(remote: str, local: str = __version__) -> bool:
    return parse_version(remote) > parse_version(local)


def _get(url: str, timeout: float = 15) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT,
                                               "Accept": "application/vnd.github+json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def release_from_json(data: dict) -> Release | None:
    assets = {a.get("name"): a.get("browser_download_url") for a in data.get("assets", [])}
    if data.get("draft") or data.get("prerelease") or ASSET_NAME not in assets:
        return None
    return Release(version=data.get("tag_name", "").lstrip("vV"), notes=data.get("body") or "",
                   exe_url=assets[ASSET_NAME], sha256_url=assets.get(ASSET_NAME + ".sha256"),
                   page_url=data.get("html_url", ""))


def check_latest(repo: str = GITHUB_REPO) -> Release | None:
    """Devolve a release mais recente se for mais nova do que esta versão."""
    data = json.loads(_get(f"https://api.github.com/repos/{repo}/releases/latest"))
    rel = release_from_json(data)
    if rel and is_newer(rel.version):
        return rel
    return None


def can_self_update() -> bool:
    """Só o .exe empacotado se atualiza sozinho (não quando corre com python)."""
    return bool(getattr(sys, "frozen", False)) and sys.platform == "win32"


def download(rel: Release) -> Path:
    data = _get(rel.exe_url, timeout=120)
    if rel.sha256_url:
        expected = _get(rel.sha256_url).decode().split()[0].lower()
        actual = hashlib.sha256(data).hexdigest()
        if actual != expected:
            raise ValueError("SHA-256 não confere; atualização descartada")
    elif len(data) < 1_000_000:
        raise ValueError("ficheiro da atualização demasiado pequeno")
    fd, tmp = tempfile.mkstemp(prefix="IqosMonitor-", suffix=".exe")
    with os.fdopen(fd, "wb") as f:
        f.write(data)
    return Path(tmp)


def install_and_restart(new_exe: Path) -> None:
    """Troca o executável e arranca a versão nova. O chamador deve sair a seguir."""
    current = Path(sys.executable)
    old = current.with_suffix(".old")
    if old.exists():
        old.unlink()
    current.rename(old)
    try:
        shutil.move(str(new_exe), str(current))  # funciona entre discos diferentes
    except OSError:
        old.rename(current)
        raise
    subprocess.Popen([str(current), "--updated"], close_fds=True)


def cleanup_old() -> None:
    if can_self_update():
        old = Path(sys.executable).with_suffix(".old")
        try:
            old.unlink(missing_ok=True)
        except OSError:
            pass
