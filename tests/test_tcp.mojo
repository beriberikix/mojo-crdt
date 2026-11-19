from std.testing import assert_equal, assert_true, assert_false, TestSuite
from std.python import Python, PythonObject
from replica import Replica
from storage import MemoryStorage
from tinydb_storage import TinyStorage
from node import sync_with, wall_ms

comptime PORT = 47210
comptime DB = "/tmp/mojo_crdt_tcp_b.json"


def cli(subprocess: PythonObject, args: List[String], wait: Bool) raises -> PythonObject:
    var cmd = Python.list("mojo", "run", "-I", "src", "examples/cli.mojo")
    for a in args:
        cmd.append(a)
    var kw = Python.dict()
    if wait:
        return subprocess.run(cmd, capture_output=True, text=True)
    return subprocess.Popen(cmd, stdout=subprocess.PIPE, text=True)


def test_sync_over_tcp_with_offline_then_online() raises:
    var os = Python.import_module("os")
    var subprocess = Python.import_module("subprocess")
    if os.path.exists(DB):
        os.remove(DB)

    # B: a persistent node with one doc, written via the CLI
    var setup = List[String]()
    for s in ["--db", DB, "--id", "B", "set", "doc1", "note", "from-B"]:
        setup.append(String(s))
    _ = cli(subprocess, setup, True)

    # A: in-process replica with its own offline edit
    var a = Replica("A", MemoryStorage())
    _ = a.local_write("doc1", "title", "from-A", wall_ms())

    # Offline: nothing listening -> clean error, local data untouched
    var failed = False
    try:
        _ = sync_with(a, "127.0.0.1", PORT)
    except:
        failed = True
    assert_true(failed)
    assert_false(Bool(a.get("doc1").value().get("note")))

    # Come online: B serves exactly one connection then exits
    var serve = List[String]()
    for s in ["--db", DB, "--id", "B", "serve", String(PORT), "1"]:
        serve.append(String(s))
    var server = cli(subprocess, serve, False)
    var line = String(py=server.stdout.readline())
    assert_true(line.startswith("listening"))

    var changed = sync_with(a, "127.0.0.1", PORT)
    assert_equal(changed, 1)
    _ = server.wait()

    # A received B's field...
    var da = a.get("doc1").value().copy()
    assert_equal(da.get("note").value(), "from-B")
    # ...and B's database file received A's (pushed over the wire)
    var b = Replica("B", TinyStorage(DB))
    var db = b.get("doc1").value().copy()
    assert_equal(db.get("title").value(), "from-A")
    assert_true(da.same_state(db))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
