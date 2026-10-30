"""Lógica de contagem e alertas, independente do Bluetooth (testável)."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime

from .protocol import BatteryStatus, Model, Telemetry

# Uma subida da bateria do carregador maior do que isto significa que está a carregar.
CHARGING_RISE_PCT = 5
# Sem telemetria: queda do holder (fora/dentro do carregador) que conta como um stick.
HOLDER_DROP_PER_STICK_PCT = 25
# Proteção contra leituras estranhas do contador do dispositivo.
MAX_STICKS_PER_UPDATE = 5


@dataclass
class Alert:
    kind: str  # "stick_end" | "holder_charge" | "low_battery" | "charged"
    title: str
    message: str


@dataclass
class DeviceState:
    address: str
    name: str
    alias: str = ""
    # Persistente
    pct_per_stick: float = 0.0
    smoking_count: int | None = None
    sticks_today: int = 0
    today: str = ""
    sticks_since_charge: int = 0
    total_sticks_seen: int = 0
    # Volátil
    connected: bool = False
    status_text: str = "Desligado"
    charger_pct: int | None = None
    holder_pct: int | None = None
    holder_in_charger: bool | None = None
    telemetry_ok: bool = False
    battery_voltage: float | None = None
    last_event: str = ""
    holder_sticks_since_charge: int = 0
    _anchor_pct: int | None = None  # bateria do carregador no último stick
    _min_pct_since_charge: int | None = None
    _charging: bool = False
    _low_alerted: bool = False
    _holder_before_removal: int | None = None

    PERSISTED = ("address", "name", "alias", "pct_per_stick", "smoking_count",
                 "sticks_today", "today", "sticks_since_charge", "total_sticks_seen")

    def __post_init__(self) -> None:
        if not self.alias:
            self.alias = self.name
        if self.pct_per_stick <= 0:
            self.pct_per_stick = 100.0 / self.model.sticks_per_full_charge

    @property
    def model(self) -> Model:
        return Model.from_name(self.name)

    def to_dict(self) -> dict:
        return {k: getattr(self, k) for k in self.PERSISTED}

    @classmethod
    def from_dict(cls, d: dict) -> "DeviceState":
        return cls(**{k: d[k] for k in cls.PERSISTED if k in d})

    @property
    def charging(self) -> bool:
        return self._charging

    # ---- Estimativas -------------------------------------------------------

    @property
    def sticks_remaining(self) -> int | None:
        """Sticks que ainda se podem fumar com a carga atual (estimativa)."""
        if self.charger_pct is None:
            return None
        from_charger = int(self.charger_pct / max(self.pct_per_stick, 0.5))
        if self.model.one_piece:
            return from_charger
        # Holder: o que ainda tem agora + recargas que o carregador consegue dar.
        holder_left = max(self.model.sticks_per_holder_charge - self.holder_sticks_since_charge, 0)
        if self.holder_in_charger and self.holder_pct is not None and self.holder_pct < 100:
            holder_left = 0  # ainda está a recarregar; a recarga sai do carregador
        return from_charger + holder_left

    # ---- Eventos -----------------------------------------------------------

    def _roll_day(self, now: datetime) -> None:
        day = now.date().isoformat()
        if self.today != day:
            self.today = day
            self.sticks_today = 0

    def on_battery(self, b: BatteryStatus, now: datetime, low_pct: int) -> list[Alert]:
        self._roll_day(now)
        alerts: list[Alert] = []
        prev_pct = self.charger_pct
        prev_in = self.holder_in_charger

        self.charger_pct = b.charger_pct
        self.holder_in_charger = b.holder_in_charger
        if b.holder_pct is not None:
            self.holder_pct = b.holder_pct

        # Holder entrou no carregador: recarrega, volta a ter sticks disponíveis.
        if b.holder_in_charger and prev_in is False:
            if (not self.telemetry_ok and self._holder_before_removal is not None
                    and b.holder_pct is not None
                    and self._holder_before_removal - b.holder_pct >= HOLDER_DROP_PER_STICK_PCT):
                alerts += self._register_sticks(1, now)
            self.holder_sticks_since_charge = 0
        if not b.holder_in_charger and prev_in:
            self._holder_before_removal = self.holder_pct

        # Deteção de carregamento do carregador / dispositivo.
        if self._min_pct_since_charge is None or b.charger_pct < self._min_pct_since_charge:
            self._min_pct_since_charge = b.charger_pct
        if b.charger_pct - self._min_pct_since_charge >= CHARGING_RISE_PCT and not self._charging:
            self._charging = True
            self._low_alerted = False
            self.sticks_since_charge = 0
            self._anchor_pct = None
            self.last_event = f"A carregar ({b.charger_pct}%)"
        if self._charging and b.charger_pct >= 100 and (prev_pct or 0) < 100:
            alerts.append(Alert("charged", "Carga completa",
                                f"{self.alias} está com 100%. Pode tirar do carregador."))
        if self._charging and prev_pct is not None and b.charger_pct < prev_pct:
            # Deixou de carregar (começou a descer outra vez).
            self._charging = False
            self._min_pct_since_charge = b.charger_pct

        alerts += self._check_low(low_pct)
        return alerts

    def on_telemetry(self, t: Telemetry, now: datetime, low_pct: int) -> list[Alert]:
        self._roll_day(now)
        if t.battery_voltage is not None:
            self.battery_voltage = t.battery_voltage
        if t.smoking_count is None:
            return []
        self.telemetry_ok = True
        alerts: list[Alert] = []
        if self.smoking_count is not None and t.smoking_count > self.smoking_count:
            n = t.smoking_count - self.smoking_count
            if n <= MAX_STICKS_PER_UPDATE:
                alerts += self._register_sticks(n, now)
        self.smoking_count = t.smoking_count
        alerts += self._check_low(low_pct)
        return alerts

    def _register_sticks(self, n: int, now: datetime) -> list[Alert]:
        self.sticks_today += n
        self.sticks_since_charge += n
        self.total_sticks_seen += n
        self.holder_sticks_since_charge += n
        self._learn(n)
        rem = self.sticks_remaining
        rem_txt = f" Restam ~{rem}." if rem is not None else ""
        self.last_event = f"Cigarro terminado às {now:%H:%M}"
        alerts = [Alert("stick_end", "Cigarro terminado",
                        f"{self.alias}: {self.sticks_today} hoje, "
                        f"{self.sticks_since_charge} desde a última carga.{rem_txt}")]
        if (not self.model.one_piece
                and self.holder_sticks_since_charge >= self.model.sticks_per_holder_charge
                and not self.holder_in_charger):
            alerts.append(Alert("holder_charge", "Ponha o holder a carregar",
                                f"{self.alias}: o holder precisa de voltar ao carregador "
                                "antes do próximo cigarro."))
        return alerts

    def _learn(self, n: int) -> None:
        """Aprende quantos % do carregador gasta cada stick (média móvel)."""
        if self.charger_pct is None:
            return
        if self._anchor_pct is not None and not self._charging:
            drop = (self._anchor_pct - self.charger_pct) / n
            if 0 < drop <= 30:
                self.pct_per_stick = round(0.8 * self.pct_per_stick + 0.2 * drop, 2)
        self._anchor_pct = self.charger_pct

    def _check_low(self, low_pct: int) -> list[Alert]:
        if self.charger_pct is None or self._charging or self._low_alerted:
            return []
        rem = self.sticks_remaining
        if self.charger_pct <= low_pct or (rem is not None and rem <= 1):
            self._low_alerted = True
            what = "o IQOS" if self.model.one_piece else "o carregador"
            return [Alert("low_battery", "Bateria fraca",
                          f"{self.alias}: {self.charger_pct}% (~{rem} cigarros). "
                          f"Ponha {what} a carregar.")]
        return []


@dataclass
class Settings:
    low_battery_pct: int = 20
    poll_seconds: int = 20
    notify_stick_end: bool = True
    auto_update: bool = True
    devices: list[DeviceState] = field(default_factory=list)
