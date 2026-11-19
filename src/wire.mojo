"""Length-prefixed text wire format for batches and sync requests.

int: `i<n>;`   str: `s<byte_len>:<bytes>` (binary/newline safe).
"""

from doc import Doc
from hlc import HLC
from replica import Batch


def put_int(mut out: String, n: Int):
    out += String("i", n, ";")


def put_str(mut out: String, s: String):
    out += String("s", s.byte_length(), ":")
    out += s


struct Reader(Movable):
    var data: String
    var pos: Int

    def __init__(out self, var data: String):
        self.data = data^
        self.pos = 0

    def _expect(mut self, tag: UInt8) raises:
        if self.pos >= self.data.byte_length() or self.data.as_bytes()[self.pos] != tag:
            raise Error("wire: bad tag at byte " + String(self.pos))
        self.pos += 1

    def _read_number(mut self, stop: UInt8) raises -> Int:
        var n = 0
        var neg = False
        var bytes = self.data.as_bytes()
        while self.pos < len(bytes) and bytes[self.pos] != stop:
            var b = bytes[self.pos]
            if b == UInt8(ord("-")):
                neg = True
            elif b >= UInt8(ord("0")) and b <= UInt8(ord("9")):
                n = n * 10 + Int(b - UInt8(ord("0")))
            else:
                raise Error("wire: bad digit")
            self.pos += 1
        self.pos += 1  # skip stop
        return -n if neg else n

    def read_int(mut self) raises -> Int:
        self._expect(UInt8(ord("i")))
        return self._read_number(UInt8(ord(";")))

    def read_str(mut self) raises -> String:
        self._expect(UInt8(ord("s")))
        var n = self._read_number(UInt8(ord(":")))
        if self.pos + n > self.data.byte_length():
            raise Error("wire: truncated string")
        var s = String(unsafe_from_utf8=self.data.as_bytes()[self.pos : self.pos + n])
        self.pos += n
        return s^


def put_batch(mut out: String, b: Batch):
    put_int(out, b.upto)
    put_int(out, len(b.docs))
    for d in b.docs:
        put_str(out, d.id)
        put_int(out, len(d.fields))
        for e in d.fields.items():
            put_str(out, e.key)
            put_str(out, e.value.value)
            put_int(out, e.value.ts.wall)
            put_int(out, e.value.ts.counter)
            put_str(out, e.value.ts.node)


def read_batch(mut r: Reader) raises -> Batch:
    var upto = r.read_int()
    var ndocs = r.read_int()
    var docs = List[Doc]()
    for _ in range(ndocs):
        var d = Doc(r.read_str())
        var nf = r.read_int()
        for _ in range(nf):
            var name = r.read_str()
            var value = r.read_str()
            var wall = r.read_int()
            var counter = r.read_int()
            var node = r.read_str()
            _ = d.set(name, value, HLC(wall, counter, node))
        docs.append(d^)
    return Batch(docs^, upto)


def encode_pull(since: Int, limit: Int) -> String:
    var s = String()
    put_str(s, "PULL")
    put_int(s, since)
    put_int(s, limit)
    return s^


def encode_push(b: Batch) -> String:
    var s = String()
    put_str(s, "PUSH")
    put_batch(s, b)
    return s^


def encode_batch(b: Batch) -> String:
    var s = String()
    put_batch(s, b)
    return s^


def encode_ack(upto: Int) -> String:
    var s = String()
    put_int(s, upto)
    return s^
