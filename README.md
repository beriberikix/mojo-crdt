# mojo-crdt

POC offline-first sync engine for a local-first document database, built to evaluate Mojo as a general-purpose language. See [MOJO_NOTES.md](MOJO_NOTES.md) for the evaluation log and verdict.

## What it is
- **CRDT:** per-field last-writer-wins documents on hybrid logical clocks (`src/hlc.mojo`, `src/doc.mojo`). Deletes are a `_deleted` field, so concurrent edit/delete merges field-wise.
- **Storage:** `Storage` trait with an in-memory Mojo backend and a TinyDB backend via Python interop (`src/storage.mojo`, `src/tinydb_storage.mojo`).
- **Sync:** RxDB-style checkpointed pull/push over batches (`src/replica.mojo`). Checkpoints are the serving peer's local `seq`, persisted per peer.
- **Transport:** deterministic in-process lossy network simulator (`src/sim.mojo`) and real TCP via libc FFI with a length-prefixed wire format (`src/net.mojo`, `src/wire.mojo`, `src/node.mojo`).

## Setup and tests
```
uv venv && uv pip install mojo tinydb
./run_tests.sh
```

## Try two nodes over TCP
```
mojo run -I src examples/cli.mojo --db a.json --id A set doc1 title "hi"
mojo run -I src examples/cli.mojo --db b.json --id B serve 47201 1 &
mojo run -I src examples/cli.mojo --db a.json --id A sync 47201
mojo run -I src examples/cli.mojo --db b.json --id B get doc1
```

## Known limits (POC)
Field values are strings; no schema, queries, or compaction (tombstones/field timestamps grow forever); single-threaded blocking server; IPv4 only; no auth/TLS; HLC high-water is persisted but physical-clock skew is not bounded.

## License

Apache License 2.0. See [LICENSE](LICENSE).
