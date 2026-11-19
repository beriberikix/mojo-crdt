"""Tiny CLI node.  mojo run -I src examples/cli.mojo --db F --id N <cmd> ...

cmds: set DOC FIELD VALUE | get DOC | serve PORT [MAX_CONNS] | sync PORT
"""

from std.sys import argv
from replica import Replica
from tinydb_storage import TinyStorage
from node import serve, sync_with, wall_ms


def main() raises:
    var args = List[String]()
    for a in argv():
        args.append(String(a))
    var db = String("")
    var id = String("node")
    var i = 1
    while i < len(args) and args[i].startswith("--"):
        if args[i] == "--db":
            db = args[i + 1]
        elif args[i] == "--id":
            id = args[i + 1]
        i += 2
    var cmd = args[i]
    var rep = Replica(id, TinyStorage(db))
    rep.load_clock()
    if cmd == "set":
        _ = rep.local_write(args[i + 1], args[i + 2], args[i + 3], wall_ms())
    elif cmd == "get":
        var d = rep.get(args[i + 1])
        if not d:
            print("(none)")
        else:
            for e in d.value().fields.items():
                print(e.key, "=", e.value.value, "@", e.value.ts)
    elif cmd == "serve":
        var n = 1
        if len(args) > i + 2:
            n = Int(args[i + 2])
        serve(rep, "127.0.0.1", Int(args[i + 1]), n)
    elif cmd == "sync":
        var n = sync_with(rep, "127.0.0.1", Int(args[i + 1]))
        print("synced; changed locally:", n)
    else:
        raise Error("unknown command " + cmd)
