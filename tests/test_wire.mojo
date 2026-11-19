from std.testing import assert_equal, assert_true, TestSuite
from doc import Doc
from hlc import HLC
from replica import Batch
from wire import Reader, encode_batch, read_batch, put_str, put_int


def test_roundtrip() raises:
    var d = Doc("doc/1")
    _ = d.set("title", "multi\nline: with 'odd' ;chars; héllo ✓", HLC(123, 4, "node-a"))
    _ = d.set("empty", "", HLC(1, 0, "n"))
    var docs = List[Doc]()
    docs.append(d^)
    docs.append(Doc("blank"))
    var b = Batch(docs^, 42)
    var r = Reader(encode_batch(b))
    var back = read_batch(r)
    assert_equal(back.upto, 42)
    assert_equal(len(back.docs), 2)
    assert_true(back.docs[0].same_state(b.docs[0]))
    assert_equal(back.docs[1].id, "blank")
    assert_equal(r.pos, r.data.byte_length())


def test_negative_and_truncated() raises:
    var s = String()
    put_int(s, -7)
    var r = Reader(s^)
    assert_equal(r.read_int(), -7)
    var bad = String()
    put_str(bad, "hello")
    var r2 = Reader(String(bad[byte=0 : bad.byte_length() - 2]))  # chop
    var raised = False
    try:
        _ = r2.read_str()
    except:
        raised = True
    assert_true(raised)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
