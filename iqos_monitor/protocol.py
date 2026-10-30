"""Protocolo BLE do IQOS (engenharia inversa, não oficial).

Fontes:
- V-VX/iqos (Rust, GPL-3.0): UUIDs, comandos SCP de telemetria e voltagem.
- mluis/iQOS.js, iYasha/iqos-api, @0x77/iqos.parser: formato da notificação
  da característica de bateria (7 bytes = holder dentro do carregador).

Nada disto está documentado pela Philip Morris; pode variar entre modelos e
versões de firmware.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum

CORE_SERVICE_UUID = "daebb240-b041-11e4-9e45-0002a5d5c51b"
BATTERY_CHAR_UUID = "f8a54120-b041-11e4-9be7-0002a5d5c51b"
SCP_CONTROL_CHAR_UUID = "e16c6e20-b041-11e4-a4c3-0002a5d5c51b"
DEVICE_STATUS_CHAR_UUID = "ecdfa4c0-b041-11e4-8b67-0002a5d5c51b"

# Pedido de telemetria (contador total de utilizações / dias de uso).
LOAD_TELEMETRY_COMMAND = bytes([0x00, 0xC9, 0x10, 0x02, 0x01, 0x01, 0x75, 0xD6])
# Pedido de voltagem da bateria.
LOAD_BATTERY_VOLTAGE_COMMAND = bytes([0x00, 0xC0, 0x00, 0x21, 0xE7])

TELEMETRY_HEADER = (0x90, 0x22)
TIMESTAMP_HEADER = (0x80, 0x02)
BATTERY_VOLTAGE_HEADER = (0x88, 0x21)
TAG_SMOKING_COUNT = 0x8E
TAG_DAY_COUNTER = 0x17
TELEMETRY_BLOCK_SIZE = 8


class Model(Enum):
    ILUMA_ONE = "ILUMA ONE"
    ILUMA = "ILUMA"
    ILUMA_PRIME = "ILUMA PRIME"
    ILUMA_I_ONE = "ILUMA i ONE"
    ILUMA_I = "ILUMA i"
    ILUMA_I_PRIME = "ILUMA i PRIME"
    IQOS_3 = "IQOS 3 / DUO"
    UNKNOWN = "IQOS"

    @classmethod
    def from_name(cls, name: str | None) -> "Model":
        n = (name or "").strip().upper()
        if "ILUMA I PRIME" in n:
            return cls.ILUMA_I_PRIME
        if "ILUMA I ONE" in n:
            return cls.ILUMA_I_ONE
        if "ILUMA I" in n:
            return cls.ILUMA_I
        if "ILUMA PRIME" in n:
            return cls.ILUMA_PRIME
        if "ILUMA ONE" in n:
            return cls.ILUMA_ONE
        if "ILUMA" in n:
            return cls.ILUMA
        if "IQOS" in n:
            return cls.IQOS_3
        return cls.UNKNOWN

    @property
    def one_piece(self) -> bool:
        """Modelos de uma só peça (sem holder separado do carregador)."""
        return self in (Model.ILUMA_ONE, Model.ILUMA_I_ONE)

    @property
    def sticks_per_full_charge(self) -> int:
        """Estimativa inicial de sticks por carga completa (carregador ou ONE).

        Valor de partida; a app aprende o consumo real de cada dispositivo.
        """
        return 20

    @property
    def sticks_per_holder_charge(self) -> int:
        """Quantos sticks seguidos o holder aguenta antes de voltar ao carregador."""
        if self.one_piece:
            return self.sticks_per_full_charge
        if self in (Model.ILUMA_I, Model.ILUMA_I_PRIME):
            return 2
        return 1


def looks_like_iqos(name: str | None, service_uuids: list[str] | None = None) -> bool:
    if service_uuids and CORE_SERVICE_UUID in [u.lower() for u in service_uuids]:
        return True
    return "IQOS" in (name or "").upper()


@dataclass(frozen=True)
class BatteryStatus:
    """Leitura da característica de bateria.

    charger_pct: bateria do carregador (ou do próprio dispositivo nos ONE).
    holder_pct: bateria do holder, só conhecida quando está dentro do carregador.
    holder_in_charger: True quando a trama tem 7 bytes.
    """

    charger_pct: int
    holder_pct: int | None
    holder_in_charger: bool


def parse_battery(frame: bytes | bytearray) -> BatteryStatus | None:
    if len(frame) < 3:
        return None
    charger = min(int(frame[2]), 100)
    if len(frame) >= 7:
        return BatteryStatus(charger, min(int(frame[6]), 100), True)
    return BatteryStatus(charger, None, False)


@dataclass
class Telemetry:
    smoking_count: int | None = None
    days_used: int | None = None
    battery_voltage: float | None = None


def telemetry_expected_length(frame: bytes | bytearray) -> int | None:
    """Comprimento total de uma resposta de telemetria, para juntar fragmentos."""
    if len(frame) >= 4 and (frame[2], frame[3]) == TELEMETRY_HEADER:
        blocks = max(frame[3] - 2, 0) // TELEMETRY_BLOCK_SIZE
        return 6 + blocks * TELEMETRY_BLOCK_SIZE
    return None


def parse_response(frame: bytes | bytearray, into: Telemetry | None = None) -> Telemetry:
    """Interpreta uma resposta SCP. Tramas desconhecidas são ignoradas."""
    t = into or Telemetry()
    if len(frame) < 4:
        return t
    header = (frame[2], frame[3])
    if header == TELEMETRY_HEADER:
        if len(frame) < 6 or int.from_bytes(frame[4:6], "little") != 0x0101:
            return t
        expected = telemetry_expected_length(frame) or 0
        if len(frame) < expected:
            return t
        for off in range(6, expected, TELEMETRY_BLOCK_SIZE):
            block = frame[off : off + TELEMETRY_BLOCK_SIZE]
            value = int.from_bytes(block[4:6], "little")
            if block[7] == TAG_SMOKING_COUNT:
                t.smoking_count = value
            elif block[7] == TAG_DAY_COUNTER:
                t.days_used = value
    elif header == TIMESTAMP_HEADER and len(frame) >= 6:
        t.days_used = int.from_bytes(frame[4:6], "little")
    elif header == BATTERY_VOLTAGE_HEADER and len(frame) >= 7:
        t.battery_voltage = int.from_bytes(frame[5:7], "little") / 1000.0
    return t
