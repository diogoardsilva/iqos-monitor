from iqos_monitor.protocol import (
    Model, Telemetry, looks_like_iqos, parse_battery, parse_response, telemetry_expected_length,
)


def test_battery_frame_with_holder_in_charger():
    b = parse_battery(bytes([0x00, 0x00, 80, 0x00, 0x00, 0x00, 100]))
    assert (b.charger_pct, b.holder_pct, b.holder_in_charger) == (80, 100, True)


def test_battery_frame_without_holder():
    b = parse_battery(bytes([0x00, 0x00, 42, 0x00]))
    assert (b.charger_pct, b.holder_pct, b.holder_in_charger) == (42, None, False)


def test_battery_frame_too_short():
    assert parse_battery(b"\x00\x01") is None


def test_battery_voltage_frame():
    t = parse_response(bytes([0x00, 0x08, 0x88, 0x21, 0x00, 0xA8, 0x10, 0x00, 0x00]))
    assert t.battery_voltage == 4.264


def test_timestamp_frame():
    assert parse_response(bytes([0x00, 0x08, 0x80, 0x02, 0x1E, 0x00, 0, 0])).days_used == 30


def telemetry_frame(count: int, days: int) -> bytes:
    head = bytes([0x00, 0x08, 0x90, 0x22, 0x01, 0x01])
    blocks = b""
    for tag, value in ((0x8E, count), (0x17, days), (0x01, 7), (0x02, 9)):
        blocks += bytes([0, 0, 0, 0]) + value.to_bytes(2, "little") + bytes([0, tag])
    return head + blocks


def test_telemetry_frame():
    f = telemetry_frame(1234, 99)
    assert telemetry_expected_length(f) == len(f) == 38
    t = parse_response(f)
    assert (t.smoking_count, t.days_used) == (1234, 99)


def test_incomplete_telemetry_is_ignored():
    assert parse_response(telemetry_frame(5, 5)[:20]).smoking_count is None


def test_unknown_frame_is_ignored():
    assert parse_response(bytes([0, 8, 0xFF, 0xFF, 0, 0])) == Telemetry()


def test_models():
    assert Model.from_name("IQOS ILUMA i PRIME") is Model.ILUMA_I_PRIME
    assert Model.from_name("IQOS ILUMA i ONE").one_piece
    assert Model.from_name("IQOS ILUMA ONE") is Model.ILUMA_ONE
    assert Model.from_name("IQOS ILUMA").sticks_per_holder_charge == 1
    assert Model.from_name("IQOS ILUMA i").sticks_per_holder_charge == 2
    assert looks_like_iqos(None, ["DAEBB240-B041-11E4-9E45-0002A5D5C51B"])
    assert not looks_like_iqos("Headphones")
