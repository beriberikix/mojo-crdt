"""Sync over TCP: server loop + client sync with persisted checkpoints."""

from std.ffi import c_int
from std.python import Python
from net import (
    tcp_listen, tcp_accept, tcp_connect, close, send_frame, recv_frame,
)
from replica import Replica
from storage import Storage
from wire import (
    Reader, encode_pull, encode_push, encode_batch, encode_ack, read_batch,
)


def wall_ms() raises -> Int:
    return Int(py=Python.import_module("time").time_ns()) // 1_000_000


def serve_connection[S: Storage](mut replica: Replica[S], fd: c_int) raises:
    """Handle requests on one connection until the peer hangs up."""
    while True:
        var msg: String
        try:
            msg = recv_frame(fd)
        except:
            return
        var r = Reader(msg^)
        var op = r.read_str()
        if op == "PULL":
            var since = r.read_int()
            var limit = r.read_int()
            send_frame(fd, encode_batch(replica.make_batch(since, limit)))
        elif op == "PUSH":
            var b = read_batch(r)
            _ = replica.apply_batch(b, wall_ms())
            send_frame(fd, encode_ack(b.upto))
        else:
            raise Error("node: unknown op " + op)


def serve[S: Storage](
    mut replica: Replica[S], ip: String, port: Int, max_conns: Int
) raises:
    var l = tcp_listen(ip, port)
    print("listening", port, flush=True)
    for _ in range(max_conns):
        var c = tcp_accept(l)
        serve_connection(replica, c)
        close(c)
    close(l)


def _cp_key(prefix: String, ip: String, port: Int) -> String:
    return String(prefix, ":", ip, ":", port)


def sync_with[S: Storage](
    mut replica: Replica[S], ip: String, port: Int, page: Int = 50
) raises -> Int:
    """Pull then push until drained. Raises if the peer is unreachable.

    Checkpoints are persisted per peer, so a restarted process resumes.
    Returns the number of docs changed locally.
    """
    var pull_key = _cp_key("pull", ip, port)
    var push_key = _cp_key("push", ip, port)
    var pull_cp = 0
    var push_cp = 0
    var s = replica.store.get_meta(pull_key)
    if s:
        pull_cp = Int(s.value())
    s = replica.store.get_meta(push_key)
    if s:
        push_cp = Int(s.value())

    var fd = tcp_connect(ip, port)
    var changed = 0
    try:
        while True:
            send_frame(fd, encode_pull(pull_cp, page))
            var r = Reader(recv_frame(fd))
            var b = read_batch(r)
            if len(b.docs) == 0:
                break
            changed += replica.apply_batch(b, wall_ms())
            pull_cp = b.upto
            replica.store.set_meta(pull_key, String(pull_cp))
        while True:
            var b = replica.make_batch(push_cp, page)
            if len(b.docs) == 0:
                break
            send_frame(fd, encode_push(b))
            var r = Reader(recv_frame(fd))
            push_cp = r.read_int()
            replica.store.set_meta(push_key, String(push_cp))
    except e:
        close(fd)
        raise e^
    close(fd)
    return changed
