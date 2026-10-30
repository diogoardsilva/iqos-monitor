from datetime import datetime, timedelta

from iqos_monitor.protocol import BatteryStatus, Telemetry
from iqos_monitor.tracker import DeviceState

NOW = datetime(2026, 10, 30, 12, 0)
LOW = 20


def kinds(alerts):
    return [a.kind for a in alerts]


def test_stick_end_from_device_counter():
    d = DeviceState("A", "IQOS ILUMA")
    d.on_battery(BatteryStatus(80, 100, True), NOW, LOW)
    assert d.on_telemetry(Telemetry(smoking_count=100), NOW, LOW) == []  # só a referência
    d.on_battery(BatteryStatus(80, None, False), NOW, LOW)
    alerts = d.on_telemetry(Telemetry(smoking_count=101), NOW, LOW)
    assert kinds(alerts) == ["stick_end", "holder_charge"]
    assert (d.sticks_today, d.sticks_since_charge) == (1, 1)


def test_iluma_i_allows_two_sticks_before_holder_alert():
    d = DeviceState("A", "IQOS ILUMA i")
    d.on_battery(BatteryStatus(80, 100, True), NOW, LOW)
    d.on_telemetry(Telemetry(smoking_count=10), NOW, LOW)
    d.on_battery(BatteryStatus(80, None, False), NOW, LOW)
    assert kinds(d.on_telemetry(Telemetry(smoking_count=11), NOW, LOW)) == ["stick_end"]
    assert "holder_charge" in kinds(d.on_telemetry(Telemetry(smoking_count=12), NOW, LOW))


def test_fallback_count_without_telemetry():
    d = DeviceState("A", "IQOS ILUMA")
    d.on_battery(BatteryStatus(80, 100, True), NOW, LOW)
    d.on_battery(BatteryStatus(80, None, False), NOW, LOW)
    alerts = d.on_battery(BatteryStatus(76, 10, True), NOW, LOW)
    assert kinds(alerts) == ["stick_end"]
    assert d.holder_sticks_since_charge == 0  # voltou ao carregador


def test_low_battery_alert_once_and_reset_on_charge():
    d = DeviceState("A", "IQOS ILUMA ONE")
    assert kinds(d.on_battery(BatteryStatus(25, None, False), NOW, LOW)) == []
    assert kinds(d.on_battery(BatteryStatus(19, None, False), NOW, LOW)) == ["low_battery"]
    assert d.on_battery(BatteryStatus(18, None, False), NOW, LOW) == []
    d.on_battery(BatteryStatus(30, None, False), NOW, LOW)  # a carregar
    assert d.sticks_since_charge == 0
    assert kinds(d.on_battery(BatteryStatus(100, None, False), NOW, LOW)) == ["charged"]


def test_remaining_estimate_and_learning():
    d = DeviceState("A", "IQOS ILUMA ONE")
    d.on_battery(BatteryStatus(100, None, False), NOW, LOW)
    assert d.sticks_remaining == 20
    d.on_telemetry(Telemetry(smoking_count=1), NOW, LOW)
    count = 1
    for pct in range(90, 40, -10):  # 10% por stick, o dobro do previsto
        count += 1
        d.on_battery(BatteryStatus(pct, None, False), NOW, LOW)
        d.on_telemetry(Telemetry(smoking_count=count), NOW, LOW)
    assert d.pct_per_stick > 7
    assert d.sticks_remaining <= 6


def test_day_rollover():
    d = DeviceState("A", "IQOS ILUMA ONE")
    d.on_battery(BatteryStatus(90, None, False), NOW, LOW)
    d.on_telemetry(Telemetry(smoking_count=1), NOW, LOW)
    d.on_telemetry(Telemetry(smoking_count=2), NOW, LOW)
    assert d.sticks_today == 1
    d.on_telemetry(Telemetry(smoking_count=3), NOW + timedelta(days=1), LOW)
    assert d.sticks_today == 1 and d.sticks_since_charge == 2


def test_persistence_roundtrip():
    d = DeviceState("A", "IQOS ILUMA", alias="Casa", sticks_today=3)
    e = DeviceState.from_dict(d.to_dict())
    assert (e.alias, e.sticks_today, e.pct_per_stick) == ("Casa", 3, 5.0)
