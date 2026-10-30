"""Ligação BLE a um IQOS (bleak usa o Bluetooth nativo do Windows/WinRT)."""

from __future__ import annotations

import asyncio
import logging
import random
from dataclasses import dataclass
from typing import Callable

from .protocol import (
    BATTERY_CHAR_UUID, LOAD_BATTERY_VOLTAGE_COMMAND, LOAD_TELEMETRY_COMMAND,
    SCP_CONTROL_CHAR_UUID, BatteryStatus, Telemetry, looks_like_iqos, parse_battery,
    parse_response, telemetry_expected_length,
)

log = logging.getLogger(__name__)

OnBattery = Callable[[BatteryStatus], None]
OnTelemetry = Callable[[Telemetry], None]
OnStatus = Callable[[bool, str], None]


@dataclass
class Found:
    address: str
    name: str
    rssi: int | None


async def scan(timeout: float = 8.0) -> list[Found]:
    from bleak import BleakScanner

    found = await BleakScanner.discover(timeout=timeout, return_adv=True)
    out = []
    for dev, adv in found.values():
        name = adv.local_name or dev.name
        if looks_like_iqos(name, adv.service_uuids):
            out.append(Found(dev.address, name or dev.address, adv.rssi))
    return sorted(out, key=lambda f: -(f.rssi or -999))


class IqosConnection:
    """Mantém um IQOS ligado: reconecta sozinho e lê a telemetria periodicamente."""

    def __init__(self, address: str, on_battery: OnBattery, on_telemetry: OnTelemetry,
                 on_status: OnStatus, poll_seconds: float = 20) -> None:
        self.address = address
        self.on_battery = on_battery
        self.on_telemetry = on_telemetry
        self.on_status = on_status
        self.poll_seconds = poll_seconds
        self._client = None
        self._task: asyncio.Task | None = None
        self._scp_frames: asyncio.Queue[bytes] = asyncio.Queue()
        self._lock = asyncio.Lock()
        self._disconnected = asyncio.Event()
        self._poke = asyncio.Event()

    def start(self) -> None:
        if self._task is None or self._task.done():
            self._task = asyncio.ensure_future(self._run())

    async def stop(self) -> None:
        if self._task:
            self._task.cancel()
            try:
                await self._task
            except (asyncio.CancelledError, Exception):
                pass
            self._task = None
        self.on_status(False, "Desligado")

    async def _run(self) -> None:
        from bleak import BleakClient

        delay = 3.0
        while True:
            self._disconnected.clear()
            self.on_status(False, "A ligar…")
            try:
                client = BleakClient(self.address, disconnected_callback=self._on_disconnect,
                                     timeout=20, pair=True)
                async with client:
                    self._client = client
                    await client.start_notify(BATTERY_CHAR_UUID, self._battery_cb)
                    await client.start_notify(SCP_CONTROL_CHAR_UUID, self._scp_cb)
                    self.on_status(True, "Ligado")
                    delay = 3.0
                    try:
                        frame = await client.read_gatt_char(BATTERY_CHAR_UUID)
                        self._battery_cb(None, bytearray(frame))
                    except Exception as e:  # algumas versões só notificam
                        log.debug("leitura da bateria falhou: %s", e)
                    await self._poll_loop()
            except asyncio.CancelledError:
                raise
            except Exception as e:
                log.warning("%s: %s", self.address, e)
                self.on_status(False, f"Sem ligação ({type(e).__name__}); nova tentativa…")
            finally:
                self._client = None
            await asyncio.sleep(delay)
            delay = min(delay * 2, 60)

    async def _poll_loop(self) -> None:
        while not self._disconnected.is_set():
            await self.refresh_telemetry()
            self._poke.clear()
            waits = [asyncio.ensure_future(self._disconnected.wait()),
                     asyncio.ensure_future(self._poke.wait())]
            try:
                await asyncio.wait(waits, timeout=self.poll_seconds,
                                   return_when=asyncio.FIRST_COMPLETED)
            finally:
                for w in waits:
                    w.cancel()

    async def refresh_telemetry(self) -> None:
        t = Telemetry()
        for cmd in (LOAD_TELEMETRY_COMMAND, LOAD_BATTERY_VOLTAGE_COMMAND):
            frame = await self._request(cmd)
            if frame:
                parse_response(frame, t)
        self.on_telemetry(t)

    async def _request(self, cmd: bytes, timeout: float = 3.0) -> bytes | None:
        client = self._client
        if client is None:
            return None
        async with self._lock:
            while not self._scp_frames.empty():
                self._scp_frames.get_nowait()
            try:
                await client.write_gatt_char(SCP_CONTROL_CHAR_UUID, cmd, response=True)
                frame = await asyncio.wait_for(self._scp_frames.get(), timeout)
                # Junta fragmentos se a resposta vier partida em várias notificações.
                expected = telemetry_expected_length(frame)
                while expected and len(frame) < expected:
                    frame += await asyncio.wait_for(self._scp_frames.get(), 0.5)
                return frame
            except Exception as e:
                log.debug("pedido %s falhou: %s", cmd.hex(), e)
                return None

    def _battery_cb(self, _char, data: bytearray) -> None:
        status = parse_battery(data)
        if status:
            self.on_battery(status)
            self._poke.set()  # mudança de estado: lê já a telemetria

    def _scp_cb(self, _char, data: bytearray) -> None:
        self._scp_frames.put_nowait(bytes(data))

    def _on_disconnect(self, _client) -> None:
        self._disconnected.set()


class SimulatedConnection(IqosConnection):
    """IQOS fictício para experimentar a app sem hardware (--demo)."""

    def __init__(self, *args, speed: float = 1.0, **kwargs) -> None:
        super().__init__(*args, **kwargs)
        self.speed = speed

    async def _run(self) -> None:
        self.on_status(False, "A ligar…")
        await asyncio.sleep(1 / self.speed)
        self.on_status(True, "Ligado (simulação)")
        charger, holder, count = random.randint(60, 100), 100, random.randint(500, 3000)
        while True:
            # Holder no carregador
            self.on_battery(BatteryStatus(charger, holder, True))
            self.on_telemetry(Telemetry(smoking_count=count, battery_voltage=3.6 + charger / 170))
            await asyncio.sleep(random.uniform(6, 12) / self.speed)
            # Tira o holder e fuma
            self.on_battery(BatteryStatus(charger, None, False))
            await asyncio.sleep(random.uniform(5, 9) / self.speed)
            count += 1
            self.on_telemetry(Telemetry(smoking_count=count))
            await asyncio.sleep(3 / self.speed)
            # Volta ao carregador e recarrega o holder
            holder = 15
            charger = max(charger - random.randint(4, 6), 0)
            self.on_battery(BatteryStatus(charger, holder, True))
            holder = 100
            if charger <= 8:
                while charger < 100:
                    await asyncio.sleep(1 / self.speed)
                    charger = min(charger + 10, 100)
                    self.on_battery(BatteryStatus(charger, holder, True))
