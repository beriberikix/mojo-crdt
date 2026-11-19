"""Minimal blocking IPv4 TCP over libc (no sockets in the Mojo stdlib)."""

from std.ffi import external_call, c_int


def _sockaddr(ip: String, port: Int) raises -> List[UInt8]:
    """struct sockaddr_in: family(LE u16) port(BE u16) addr(4) zero(8)."""
    var sa = List[UInt8](length=16, fill=0)
    sa[0] = 2  # AF_INET
    sa[2] = UInt8((port >> 8) & 0xFF)
    sa[3] = UInt8(port & 0xFF)
    var parts = ip.split(".")
    if len(parts) != 4:
        raise Error("net: bad ipv4 " + ip)
    for i in range(4):
        sa[4 + i] = UInt8(Int(parts[i]))
    return sa^


def _check(rc: c_int, what: String) raises -> c_int:
    if rc < 0:
        raise Error("net: " + what + " failed")
    return rc


def tcp_listen(ip: String, port: Int) raises -> c_int:
    var fd = _check(external_call["socket", c_int](c_int(2), c_int(1), c_int(0)), "socket")
    var one = List[c_int](length=1, fill=1)
    _ = _check(
        external_call["setsockopt", c_int](
            fd, c_int(1), c_int(2), one.unsafe_ptr(), c_int(4)
        ),
        "setsockopt",
    )
    var sa = _sockaddr(ip, port)
    _ = _check(external_call["bind", c_int](fd, sa.unsafe_ptr(), c_int(16)), "bind")
    _ = _check(external_call["listen", c_int](fd, c_int(16)), "listen")
    return fd


def tcp_accept(listener: c_int) raises -> c_int:
    return _check(
        external_call["accept", c_int](listener, Int(0), Int(0)), "accept"
    )


def tcp_connect(ip: String, port: Int) raises -> c_int:
    var fd = _check(external_call["socket", c_int](c_int(2), c_int(1), c_int(0)), "socket")
    var sa = _sockaddr(ip, port)
    var rc = external_call["connect", c_int](fd, sa.unsafe_ptr(), c_int(16))
    if rc < 0:
        _ = external_call["close", c_int](fd)
        raise Error("net: connect failed (offline?)")
    return fd


def close(fd: c_int):
    _ = external_call["close", c_int](fd)


def send_all(fd: c_int, data: String) raises:
    var bytes = data.as_bytes()
    var sent = 0
    while sent < len(bytes):
        var n = external_call["send", Int](
            fd, bytes.unsafe_ptr().unsafe_offset(sent), len(bytes) - sent, c_int(0x4000)  # MSG_NOSIGNAL
        )
        if n <= 0:
            raise Error("net: send failed")
        sent += n


def recv_exact(fd: c_int, n: Int) raises -> String:
    var buf = List[UInt8](length=n, fill=0)
    var got = 0
    while got < n:
        var r = external_call["recv", Int](fd, buf.unsafe_ptr().unsafe_offset(got), n - got, c_int(0))
        if r <= 0:
            raise Error("net: connection closed")
        got += r
    return String(unsafe_from_utf8=Span(buf))


def send_frame(fd: c_int, payload: String) raises:
    var n = String(payload.byte_length())
    var header = String()
    for _ in range(8 - n.byte_length()):
        header += "0"
    send_all(fd, header + n + payload)


def recv_frame(fd: c_int) raises -> String:
    var h = recv_exact(fd, 8)
    var n = Int(h)
    return recv_exact(fd, n)
