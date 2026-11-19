"""Per-field last-writer-wins document. Deletion is the `_deleted` field."""

from hlc import HLC

comptime DELETED = "_deleted"


@fieldwise_init
struct Field(Copyable):
    var value: String
    var ts: HLC


struct Doc(Copyable, Movable):
    var id: String
    var fields: Dict[String, Field]

    def __init__(out self, id: String):
        self.id = id
        self.fields = Dict[String, Field]()

    def __init__(out self, *, copy: Self):
        self.id = copy.id
        self.fields = copy.fields.copy()

    def set(mut self, name: String, value: String, ts: HLC) -> Bool:
        """Apply a field write. Returns True if it changed state."""
        var existing = self.fields.get(name)
        if existing:
            if not (existing.value().ts < ts):
                return False
        self.fields[name] = Field(value, ts.copy())
        return True

    def get(self, name: String) -> Optional[String]:
        var f = self.fields.get(name)
        if f:
            return f.value().value.copy()
        return None

    def is_deleted(self) -> Bool:
        var d = self.get(DELETED)
        if d:
            return d.value() == "true"
        return False

    def merge(mut self, other: Self) -> Bool:
        """State-based merge: commutative, associative, idempotent.

        Returns True if any field changed.
        """
        var changed = False
        for entry in other.fields.items():
            if self.set(entry.key, entry.value.value, entry.value.ts):
                changed = True
        return changed

    def same_state(self, other: Self) -> Bool:
        if len(self.fields) != len(other.fields):
            return False
        for entry in self.fields.items():
            var o = other.fields.get(entry.key)
            if not o:
                return False
            if not (o.value().ts == entry.value.ts) or o.value().value != entry.value.value:
                return False
        return True
