from std.testing import assert_equal, assert_true, assert_false, TestSuite
from hlc import HLC, HLCClock
from doc import Doc, DELETED


def test_tick_monotonic() raises:
    var c = HLCClock("a")
    var t1 = c.tick(100)
    var t2 = c.tick(100)  # same physical ms -> counter bumps
    var t3 = c.tick(50)  # clock went backwards -> still monotonic
    assert_true(t1 < t2)
    assert_true(t2 < t3)
    assert_equal(t2.counter, 1)


def test_observe_orders_after_remote() raises:
    var a = HLCClock("a")
    var b = HLCClock("b")
    var ta = a.tick(1000)
    var tb = b.observe(ta, 10)  # b's physical clock is far behind
    assert_true(ta < tb)
    assert_equal(tb.wall, 1000)


def test_tiebreak_by_node() raises:
    assert_true(HLC(1, 0, "a") < HLC(1, 0, "b"))
    assert_false(HLC(1, 0, "a") == HLC(1, 0, "b"))


def test_lww_field() raises:
    var d = Doc("x")
    assert_true(d.set("title", "new", HLC(2, 0, "a")))
    assert_false(d.set("title", "old", HLC(1, 0, "b")))  # older loses
    assert_equal(d.get("title").value(), "new")


def test_merge_commutes() raises:
    var a = Doc("x")
    var b = Doc("x")
    _ = a.set("title", "A", HLC(5, 0, "a"))
    _ = a.set("n", "1", HLC(1, 0, "a"))
    _ = b.set("title", "B", HLC(5, 0, "b"))  # same wall: node breaks tie
    _ = b.set("m", "2", HLC(2, 0, "b"))
    var ab = a.copy()
    ab.merge(b)
    var ba = b.copy()
    ba.merge(a)
    assert_true(ab.same_state(ba))
    assert_equal(ab.get("title").value(), "B")
    assert_equal(ab.get("n").value(), "1")
    assert_equal(ab.get("m").value(), "2")


def test_merge_idempotent() raises:
    var a = Doc("x")
    var b = Doc("x")
    _ = a.set("t", "A", HLC(1, 0, "a"))
    _ = b.set("t", "B", HLC(2, 0, "b"))
    a.merge(b)
    var once = a.copy()
    a.merge(b)
    assert_true(a.same_state(once))


def test_tombstone() raises:
    var d = Doc("x")
    _ = d.set("t", "v", HLC(1, 0, "a"))
    _ = d.set(DELETED, "true", HLC(2, 0, "a"))
    assert_true(d.is_deleted())
    _ = d.set(DELETED, "false", HLC(3, 0, "b"))  # later write resurrects
    assert_false(d.is_deleted())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
