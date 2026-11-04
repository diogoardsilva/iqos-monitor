from datetime import date, datetime

from iqos_monitor import storage
from iqos_monitor.stock import Stock
from iqos_monitor.tracker import Settings

NOW = datetime(2026, 11, 4, 10, 0)


def kinds(alerts):
    return [a.kind for a in alerts]


def smoke(s: Stock, n: int) -> list[str]:
    out = []
    for _ in range(n):
        out += kinds(s.consume(1))
    return out


def test_no_stock_no_alerts():
    s = Stock()
    assert s.consume(3) == []
    assert s.sticks_left is None


def test_buy_three_cartons():
    s = Stock(pack_size=20, packs_per_carton=10)
    s.add(cartons=3, now=NOW)
    assert s.sticks_left == 600
    assert s.describe() == "3 volumes"
    assert s.since == "2026-11-04"
    s.add(packs=2)
    assert s.describe() == "3 volumes e 2 maços"


def test_pack_low_once_per_pack():
    s = Stock(pack_size=10, packs_per_carton=10, pack_warn_sticks=2, low_stock_packs=0)
    s.add(packs=2, now=NOW)
    # 1.º maço: fuma 7 sem avisos, o 8.º deixa 2 no maço.
    assert smoke(s, 7) == []
    assert kinds(s.consume(1)) == ["pack_low"]
    assert smoke(s, 1) == []           # resta 1: não repete
    assert smoke(s, 1) == []           # maço acabou, abre o 2.º (10)
    assert s.open_pack_left == 10 and s.closed_packs == 0
    assert smoke(s, 7) == []
    alerts = s.consume(1)
    assert kinds(alerts) == ["pack_low"]
    assert "último maço" in alerts[0].message


def test_pack_done_when_warn_is_zero():
    s = Stock(pack_size=10, pack_warn_sticks=0, low_stock_packs=0)
    s.add(packs=2)
    assert smoke(s, 9) == []
    alerts = s.consume(1)
    assert kinds(alerts) == ["pack_low"]
    assert alerts[0].title == "Maço acabado"


def test_low_stock_at_one_carton():
    s = Stock(pack_size=10, packs_per_carton=10, low_stock_packs=10, pack_warn_sticks=0)
    s.add(cartons=3)
    got = smoke(s, 200)                # fuma 2 volumes
    assert got.count("stock_low") == 1
    assert s.sticks_left == 100
    assert smoke(s, 1).count("stock_low") == 0


def test_empty():
    s = Stock(pack_size=10, low_stock_packs=0, pack_warn_sticks=0)
    s.set(2)
    assert smoke(s, 1) == []
    assert kinds(s.consume(5)) == ["stock_empty"]
    assert s.sticks_left == 0
    assert s.consume(1) == []          # já sem tabaco: não volta a avisar


def test_notify_off():
    s = Stock(pack_size=10, notify=False)
    s.set(3)
    assert s.consume(3) == []
    assert s.sticks_left == 0


def test_days_left():
    s = Stock(pack_size=20)
    s.add(packs=10, now=datetime(2026, 11, 1))
    s.consume(40)                      # 40 sticks em 4 dias = 10/dia
    assert s.per_day(date(2026, 11, 4)) == 10
    assert s.days_left(date(2026, 11, 4)) == 16


def test_storage_roundtrip(tmp_path):
    st = Settings()
    st.stock.add(cartons=1, now=NOW)
    st.stock.pack_size = 10
    p = tmp_path / "state.json"
    storage.save(st, p)
    back = storage.load(p)
    assert back.stock == st.stock
    assert storage.load(tmp_path / "nada.json").stock.sticks_left is None
