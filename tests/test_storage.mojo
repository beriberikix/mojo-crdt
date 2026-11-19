from std.testing import assert_equal, assert_true, assert_false, TestSuite
from std.python import Python
from doc import Doc
from hlc import HLC
from storage import Storage, MemoryStorage
from tinydb_storage import TinyStorage


def check_storage[S: Storage](mut s: S) raises:
    assert_equal(s.last_seq(), 0)
    assert_false(Bool(s.get("a")))

    var a = Doc("a")
    _ = a.set("title", "hi", HLC(1, 0, "n1"))
    assert_equal(s.put(a), 1)
    var b = Doc("b")
    _ = b.set("x", "1", HLC(2, 3, "n2"))
    assert_equal(s.put(b), 2)
    # update a -> new seq, old seq no longer returned for `a`
    _ = a.set("title", "yo", HLC(5, 0, "n1"))
    assert_equal(s.put(a), 3)

    var got = s.get("a").value().copy()
    assert_equal(got.get("title").value(), "yo")
    assert_true(got.same_state(a))

    var all = s.changes_since(0)
    assert_equal(len(all), 2)
    assert_equal(all[0].doc.id, "b")  # seq 2
    assert_equal(all[1].doc.id, "a")  # seq 3
    assert_equal(len(s.changes_since(2)), 1)
    assert_equal(len(s.changes_since(3)), 0)
    assert_equal(s.last_seq(), 3)


def test_memory() raises:
    var s = MemoryStorage()
    check_storage(s)


def test_tinydb_memory() raises:
    var s = TinyStorage("")
    check_storage(s)


def test_tinydb_file_persists() raises:
    var path = "/tmp/mojo_crdt_test_storage.json"
    var os = Python.import_module("os")
    if os.path.exists(path):
        os.remove(path)
    var s = TinyStorage(path)
    var d = Doc("p")
    _ = d.set("k", "v", HLC(9, 1, "z"))
    _ = s.put(d)
    s.db.close()
    var s2 = TinyStorage(path)
    assert_equal(s2.last_seq(), 1)
    assert_true(s2.get("p").value().same_state(d))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
