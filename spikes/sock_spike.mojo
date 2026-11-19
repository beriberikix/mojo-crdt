from std.ffi import external_call, c_int


def main() raises:
    var fd = external_call["socket", c_int](c_int(2), c_int(1), c_int(0))
    print("socket fd:", fd)
    var rc = external_call["close", c_int](fd)
    print("close:", rc)
