"""Stock de tabaco: o que o utilizador comprou, descontado a cada cigarro.

É partilhado por todos os IQOS (os sticks saem todos do mesmo sítio). Avisa
quando o maço aberto está a acabar, quando o stock fica baixo e quando acaba.
"""

from __future__ import annotations

from dataclasses import dataclass, fields
from datetime import date, datetime

from .tracker import Alert


def _plural(n: int, one: str, many: str) -> str:
    return f"{n} {one if n == 1 else many}"


@dataclass
class Stock:
    # None = o utilizador ainda não disse quanto tabaco tem (não há avisos).
    sticks_left: int | None = None
    pack_size: int = 20          # sticks por maço
    packs_per_carton: int = 10   # maços por volume
    pack_warn_sticks: int = 2    # avisar quando restam isto no maço aberto (0 = quando acaba)
    low_stock_packs: int = 10    # avisar quando restam isto em maços (10 = 1 volume)
    notify: bool = True
    # Para estimar quantos dias dá o stock.
    since: str = ""              # data (AAAA-MM-DD) desde a qual contamos o consumo
    consumed: int = 0            # sticks fumados desde essa data

    @classmethod
    def from_dict(cls, d: dict | None) -> "Stock":
        names = {f.name for f in fields(cls)}
        return cls(**{k: v for k, v in (d or {}).items() if k in names})

    def to_dict(self) -> dict:
        return {f.name: getattr(self, f.name) for f in fields(self)}

    # ---- Contas ------------------------------------------------------------

    @property
    def tracking(self) -> bool:
        return self.sticks_left is not None

    @property
    def carton_size(self) -> int:
        return self.pack_size * self.packs_per_carton

    @property
    def low_stock_sticks(self) -> int:
        return self.low_stock_packs * self.pack_size

    @staticmethod
    def _open_left(s: int, pack: int) -> int:
        """Sticks no maço aberto (o maço que está a ser fumado)."""
        return 0 if s <= 0 else (s - 1) % pack + 1

    @property
    def open_pack_left(self) -> int:
        return self._open_left(self.sticks_left or 0, self.pack_size)

    @property
    def closed_packs(self) -> int:
        """Maços por abrir, além do que está aberto."""
        s = self.sticks_left or 0
        return (s - self.open_pack_left) // self.pack_size

    def describe(self, sticks: int | None = None) -> str:
        """Ex.: "2 volumes, 3 maços e 7 sticks"."""
        s = self.sticks_left if sticks is None else sticks
        if not s or s <= 0:
            return "sem tabaco"
        cartons, rest = divmod(s, self.carton_size)
        packs, loose = divmod(rest, self.pack_size)
        parts = []
        if cartons:
            parts.append(_plural(cartons, "volume", "volumes"))
        if packs:
            parts.append(_plural(packs, "maço", "maços"))
        if loose:
            parts.append(_plural(loose, "stick", "sticks"))
        return parts[0] if len(parts) == 1 else ", ".join(parts[:-1]) + " e " + parts[-1]

    def per_day(self, today: date) -> float | None:
        """Média de sticks por dia desde que começámos a contar."""
        if not self.since or self.consumed <= 0:
            return None
        try:
            start = date.fromisoformat(self.since)
        except ValueError:
            return None
        days = max((today - start).days + 1, 1)
        return self.consumed / days

    def days_left(self, today: date) -> int | None:
        avg = self.per_day(today)
        if avg is None or not self.tracking or avg <= 0:
            return None
        return int((self.sticks_left or 0) / avg)

    # ---- Ações do utilizador ----------------------------------------------

    def add(self, cartons: int = 0, packs: int = 0, sticks: int = 0, now: datetime | None = None) -> None:
        """Comprei tabaco."""
        n = cartons * self.carton_size + packs * self.pack_size + sticks
        if n <= 0:
            return
        self._start(now)
        self.sticks_left = (self.sticks_left or 0) + n

    def set(self, sticks: int, now: datetime | None = None) -> None:
        """Corrigir: tenho exatamente isto."""
        self._start(now)
        self.sticks_left = max(int(sticks), 0)

    def stop(self) -> None:
        """Deixar de contar o stock."""
        self.sticks_left = None
        self.since = ""
        self.consumed = 0

    def _start(self, now: datetime | None) -> None:
        if not self.since:
            self.since = (now or datetime.now()).date().isoformat()
            self.consumed = 0

    # ---- Consumo -----------------------------------------------------------

    def consume(self, n: int) -> list[Alert]:
        """Desconta n sticks fumados e devolve os avisos que isso provoca."""
        if not self.tracking or n <= 0:
            return []
        before = self.sticks_left or 0
        after = max(before - n, 0)
        self.sticks_left = after
        self.consumed += min(n, before)
        if not self.notify or before <= 0:
            return []

        if after == 0:
            return [Alert("stock_empty", "Acabou o tabaco",
                          "Fumou o último stick. Registe a próxima compra para voltar a contar.")]

        alerts: list[Alert] = []
        low = self.low_stock_sticks
        if before > low >= after:
            alerts.append(Alert("stock_low", "Está a acabar o tabaco",
                                f"Resta {self.describe(after)}. Está na altura de comprar."))

        pack = self.pack_size
        open_before = self._open_left(before, pack)
        open_after = self._open_left(after, pack)
        new_pack = (before - 1) // pack != (after - 1) // pack
        warn = self.pack_warn_sticks
        if warn > 0 and open_after <= warn and (open_before > warn or new_pack):
            left = (after - open_after) // pack
            then = (f"Depois disso tem {_plural(left, 'maço', 'maços')}." if left
                    else "É o último maço.")
            alerts.append(Alert("pack_low", "O maço está a acabar",
                                f"Restam {_plural(open_after, 'stick', 'sticks')} neste maço. {then}"))
        elif warn <= 0 and after % pack == 0 and new_pack:
            alerts.append(Alert("pack_low", "Maço acabado",
                                f"Abra um maço novo. Resta {self.describe(after)}."))
        return alerts
