"""TinyDB-backed Storage via Python interop."""

from std.python import Python, PythonObject
from doc import Doc, Field
from hlc import HLC
from storage import Storage, Row, sort_rows


struct TinyStorage(Storage):
    var db: PythonObject
    var table: PythonObject
    var query: PythonObject
    var seq: Int

    def __init__(out self, path: String) raises:
        """Empty `path` means in-memory."""
        var tinydb = Python.import_module("tinydb")
        if path == "":
            var storages = Python.import_module("tinydb.storages")
            self.db = tinydb.TinyDB(storage=storages.MemoryStorage)
        else:
            self.db = tinydb.TinyDB(path)
        self.table = self.db.table("docs")
        self.query = tinydb.Query()
        self.seq = 0
        for item in self.table.all():
            var s = Int(py=item["seq"])
            if s > self.seq:
                self.seq = s

    def get(self, id: String) raises -> Optional[Doc]:
        var found = self.table.search(self.query.id == id)
        if len(found) == 0:
            return None
        return Self._decode(found[0])

    def put(mut self, doc: Doc) raises -> Int:
        self.seq += 1
        var fields = Python.dict()
        for entry in doc.fields.items():
            var f = entry.value.copy()
            fields[entry.key] = Python.list(
                f.value, f.ts.wall, f.ts.counter, f.ts.node
            )
        var rec = Python.dict()
        rec["id"] = doc.id
        rec["seq"] = self.seq
        rec["fields"] = fields
        _ = self.table.upsert(rec, self.query.id == doc.id)
        return self.seq

    def changes_since(self, seq: Int) raises -> List[Row]:
        var out = List[Row]()
        for item in self.table.search(self.query.seq > seq):
            out.append(Row(Self._decode(item), Int(py=item["seq"])))
        sort_rows(out)
        return out^

    def last_seq(self) raises -> Int:
        return self.seq

    @staticmethod
    def _decode(item: PythonObject) raises -> Doc:
        var d = Doc(String(py=item["id"]))
        for kv in item["fields"].items():
            var v = kv[1]
            _ = d.set(
                String(py=kv[0]),
                String(py=v[0]),
                HLC(Int(py=v[1]), Int(py=v[2]), String(py=v[3])),
            )
        return d^
