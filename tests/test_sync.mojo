from std.testing import assert_equal, assert_true, assert_false, TestSuite
from doc import Doc, DELETED
from hlc import HLC
from replica import Replica
from storage import MemoryStorage, Storage
from tinydb_storage import TinyStorage
from sim import Cluster, Rng


def mem_cluster(n: Int, page: Int = 3) -> Cluster[MemoryStorage]:
    var rs = List[Replica[MemoryStorage]]()
    for i in range(n):
        rs.append(Replica(String("r", i), MemoryStorage()))
    return Cluster(rs^, page)


def test_two_replicas_offline_edits_merge() raises:
    var c = mem_cluster(2)
    _ = c.write(0, "d1", "title", "from-a", 1)
    _ = c.write(0, "d1", "a_only", "1", 2)
    _ = c.write(1, "d1", "b_only", "2", 3)
    c.settle(10)
    var ids = List[String]()
    ids.append("d1")
    assert_true(c.converged(ids))
    var d = c.replicas[1].get("d1").value().copy()
    assert_equal(d.get("a_only").value(), "1")
    assert_equal(d.get("b_only").value(), "2")


def test_concurrent_same_field_lww() raises:
    var c = mem_cluster(2)
    var t0 = c.write(0, "d", "f", "early", 1)
    var t1 = c.write(1, "d", "f", "late", 500)  # later physical time
    c.settle(1000)
    assert_true(t0 < t1)
    assert_equal(c.replicas[0].get("d").value().get("f").value(), "late")


def test_delete_vs_edit() raises:
    var c = mem_cluster(2)
    _ = c.write(0, "d", "f", "v", 1)
    c.settle(10)
    _ = c.write(0, "d", DELETED, "true", 100)
    _ = c.write(1, "d", "f", "edited", 200)  # concurrent, doesn't touch _deleted
    c.settle(300)
    var d = c.replicas[1].get("d").value().copy()
    assert_true(d.is_deleted())
    assert_equal(d.get("f").value(), "edited")  # field-level merge keeps edit


def test_pagination() raises:
    var c = mem_cluster(2, page=2)
    for k in range(7):
        _ = c.write(0, String("doc", k), "v", String(k), k)
    c.settle(100)
    for k in range(7):
        assert_true(c.replicas[1].get(String("doc", k)).value().get("v").value() == String(k))


def test_no_echo_storms() raises:
    var c = mem_cluster(2)
    _ = c.write(0, "d", "f", "v", 1)
    c.settle(10)
    var seq_before = c.replicas[0].store.last_seq()
    c.settle(20)  # nothing new: nothing should be re-stored
    assert_equal(c.replicas[0].store.last_seq(), seq_before)


def fuzz[S: Storage](mut c: Cluster[S], seed: Int, steps: Int) raises:
    var rng = Rng(seed)
    var n = c.n()
    for i in range(n):
        c.skew[i] = rng.below(20000) - 10000  # +/- 10s clock skew
    var ids = List[String]()
    for k in range(4):
        ids.append(String("doc", k))
    # oracle: best (ts, value) per doc/field across ALL writes
    var best = Dict[String, HLC]()
    var best_val = Dict[String, String]()
    for step in range(steps):
        var action = rng.below(10)
        if action < 5:
            var i = rng.below(n)
            var id = ids[rng.below(len(ids))]
            var field = String("f", rng.below(3))
            if rng.chance(8):
                field = DELETED
            var val = String("v", step)
            if field == DELETED:
                val = "true" if rng.chance(70) else "false"
            var ts = c.write(i, id, field, val, step)
            var key = id + "/" + field
            var cur = best.get(key)
            if (not cur) or cur.value() < ts:
                best[key] = ts.copy()
                best_val[key] = val
        elif action < 9:
            var i = rng.below(n)
            var j = rng.below(n)
            if i != j:
                c.sync_pair(i, j, step, rng, 25, 20, 20)
        else:
            c.deliver_one_delayed(step, rng)
    c.settle(steps + 1)
    assert_true(c.converged(ids))
    # converged state must equal the oracle (true LWW semantics)
    for entry in best_val.items():
        var parts = entry.key.split("/")
        var d = c.replicas[0].get(String(parts[0])).value().copy()
        assert_equal(d.get(String(parts[1])).value(), entry.value)


def test_fuzz_memory() raises:
    for seed in range(1, 41):
        var c = mem_cluster(3)
        fuzz(c, seed, 120)


def test_fuzz_tinydb() raises:
    for seed in range(1, 4):
        var rs = List[Replica[TinyStorage]]()
        for i in range(3):
            rs.append(Replica(String("r", i), TinyStorage("")))
        var c = Cluster(rs^, 3)
        fuzz(c, seed, 60)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
