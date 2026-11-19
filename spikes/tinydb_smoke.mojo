from std.python import Python, PythonObject


def main() raises:
    var tinydb = Python.import_module("tinydb")
    var storages = Python.import_module("tinydb.storages")

    # In-memory TinyDB
    var db = tinydb.TinyDB(storage=storages.MemoryStorage)
    var docs = db.table("docs")
    _ = docs.insert(Python.dict(id="a", title="hello"))
    var rows = docs.all()
    print("mem rows:", len(rows))
    print("title:", String(py=rows[0]["title"]))

    # File-backed TinyDB
    var fdb = tinydb.TinyDB("/tmp/mojo_crdt_smoke.json")
    _ = fdb.table("docs").insert(Python.dict(id="f"))
    print("file rows:", len(fdb.table("docs").all()))
    fdb.close()
