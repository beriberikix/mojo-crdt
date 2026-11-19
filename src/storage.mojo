"""Storage interface + in-memory backend.

Every state change bumps a local, monotonically increasing `seq` on the doc.
Replication checkpoints are seqs of the *serving* replica, so merged remote
changes are still discoverable by downstream peers (HLC order alone is not).
"""

from doc import Doc


@fieldwise_init
struct Row(Copyable):
    var doc: Doc
    var seq: Int


def sort_rows(mut rows: List[Row]):
    """Ascending by seq (insertion sort; change sets are small)."""
    for i in range(1, len(rows)):
        var j = i
        while j > 0 and rows[j].seq < rows[j - 1].seq:
            rows.swap_elements(j, j - 1)
            j -= 1


trait Storage(Movable):
    def get(self, id: String) raises -> Optional[Doc]: ...
    def put(mut self, doc: Doc) raises -> Int: ...
    def changes_since(self, seq: Int) raises -> List[Row]: ...
    def last_seq(self) raises -> Int: ...


struct MemoryStorage(Storage):
    var docs: Dict[String, Row]
    var seq: Int

    def __init__(out self):
        self.docs = Dict[String, Row]()
        self.seq = 0

    def get(self, id: String) raises -> Optional[Doc]:
        var r = self.docs.get(id)
        if r:
            return r.value().doc.copy()
        return None

    def put(mut self, doc: Doc) raises -> Int:
        self.seq += 1
        self.docs[doc.id] = Row(doc.copy(), self.seq)
        return self.seq

    def changes_since(self, seq: Int) raises -> List[Row]:
        var out = List[Row]()
        for entry in self.docs.items():
            if entry.value.seq > seq:
                out.append(entry.value.copy())
        sort_rows(out)
        return out^

    def last_seq(self) raises -> Int:
        return self.seq
