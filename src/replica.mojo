"""A replica: local DB + HLC + batch-based pull/push replication primitives."""

from doc import Doc
from hlc import HLC, HLCClock
from storage import Storage


@fieldwise_init
struct Batch(Copyable):
    """A page of changed docs from a peer, plus the checkpoint to resume from."""

    var docs: List[Doc]
    var upto: Int


struct Replica[S: Storage](Movable):
    var id: String
    var clock: HLCClock
    var store: Self.S

    def __init__(out self, id: String, var store: Self.S):
        self.id = id
        self.clock = HLCClock(id)
        self.store = store^

    def local_write(
        mut self, doc_id: String, field: String, value: String, now: Int
    ) raises -> HLC:
        var doc = Doc(doc_id)
        var existing = self.store.get(doc_id)
        if existing:
            doc = existing.value().copy()
        var ts = self.clock.tick(now)
        _ = doc.set(field, value, ts)
        _ = self.store.put(doc)
        return ts^

    def get(self, doc_id: String) raises -> Optional[Doc]:
        return self.store.get(doc_id)

    def make_batch(self, since: Int, limit: Int) raises -> Batch:
        """Serve changes with seq > since, at most `limit` docs."""
        var rows = self.store.changes_since(since)
        var docs = List[Doc]()
        var upto = since
        for r in rows:
            if len(docs) >= limit:
                break
            docs.append(r.doc.copy())
            upto = r.seq
        return Batch(docs^, upto)

    def apply_batch(mut self, batch: Batch, now: Int) raises -> Int:
        """Merge remote docs; only changed docs are re-stored (no echo)."""
        var changed = 0
        var newest = HLC(0, 0, "")
        for d in batch.docs:
            for entry in d.fields.items():
                if newest < entry.value.ts:
                    newest = entry.value.ts.copy()
            var local = self.store.get(d.id)
            if local:
                var merged = local.value().copy()
                if merged.merge(d):
                    _ = self.store.put(merged)
                    changed += 1
            else:
                _ = self.store.put(d)
                changed += 1
        if len(batch.docs) > 0:
            _ = self.clock.observe(newest, now)
        return changed
