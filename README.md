# mojo-crdt

POC offline-first sync engine for a local-first document database, built to evaluate Mojo as a general-purpose language.

## Design
- Pure Mojo core: hybrid logical clocks, per-field LWW documents with tombstones, merge, RxDB-style checkpoint pull/push replication.
- `Storage` trait with a TinyDB backend (via Python interop) and an in-memory Mojo backend.
- Transport: in-process simulated network first, then TCP.
- Findings are logged in `MOJO_NOTES.md`.

## Setup
```
uv venv && uv pip install mojo tinydb
source .venv/bin/activate
```
