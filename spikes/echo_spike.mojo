from std.ffi import c_int
from net import tcp_listen, tcp_accept, tcp_connect, send_frame, recv_frame, close


def main() raises:
    var l = tcp_listen("127.0.0.1", 47123)
    var c = tcp_connect("127.0.0.1", 47123)  # backlog lets us connect before accept
    var s = tcp_accept(l)
    send_frame(c, "hello\nwörld")
    print(recv_frame(s))
    close(c)
    close(s)
    close(l)
