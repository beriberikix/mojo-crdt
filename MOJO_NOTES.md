# Mojo evaluation notes

Running log of friction, gaps, and wins. Newest last.

## Environment
- Mojo 1.2.0 (2016d0cd) from PyPI via `uv`, CPython 3.14.4, Linux x86_64.

## M1: toolchain + Python interop
- **Win:** `uv pip install mojo` is a one-liner; `mojo run file.mojo` just works.
- **Win:** Python interop found TinyDB in the venv without extra config (`Python.import_module`), in-memory and file-backed. `String(py=...)` conversion works.
- **Friction:** every `mojo` run prints `HSA exception: Agent creation failed. The GPU node uses a deprecated doorbell type` on this machine (GPU probe, harmless for CPU code). Noise on every invocation.
- **Friction:** pretrained syntax knowledge is stale (`fn`, `alias`, `from collections` are all removed); the bundled skills are required reading.
- Python errors surface as Mojo `Error` with the original message (a wrong `TinyDB(...)` call was reported clearly).

## M2: HLC + per-field LWW doc (`src/hlc.mojo`, `src/doc.mojo`)
- **Win:** 7 unit tests passed on first compile after following the skill's syntax rules (`def`, `Self`-style traits, `Dict.get` returning `Optional`).
- **Win:** `mojo run -I src tests/...` gives simple multi-file module imports; `TestSuite.discover_tests` works as a runner.
- **Friction:** non-`ImplicitlyCopyable` structs (anything holding `String`/`Dict`) need explicit `.copy()` everywhere (e.g. `ts.copy()`, `existing.value().ts`); verbose but caught mistakes at compile time.
- **Friction:** `Doc` needed a hand-written copy constructor because `Dict` isn't implicitly copyable and I wanted `Copyable` for merge tests.
- Design: field values are `String` for now (typed values deferred); deletion is a normal LWW field `_deleted`, so concurrent delete/edit resolves by timestamp.

## M3: Storage trait + MemoryStorage + TinyStorage (`src/storage.mojo`, `src/tinydb_storage.mojo`)
- **Win:** a real `trait Storage` with two backends and a generic `check_storage[S: Storage](mut s: S)` test shared by both worked cleanly; static dispatch, no boxing.
- **Win:** TinyDB persistence round-trips through Python interop (dict/list building with `Python.dict()`, `Python.list(...)`, iteration over `.items()`).
- **Friction:** `swap(list[j], list[j-1])` is rejected as mutable aliasing even for distinct indices; use `List.swap_elements(i, j)`.
- **Friction:** every `Optional[Doc]` unwrap and `entry.value` read needs `.copy()` for non-implicitly-copyable structs.
- **Bug/oddity:** `TestSuite` reports wildly wrong per-test durations (e.g. 49-80 s for a test when the whole run took 1.5 s wall). Timer artifact; ignore the numbers.
- Design: each state change bumps a local `seq`; replication checkpoints will be the serving replica's seq (HLC order alone can't find merged remote changes).

## M4: Replica + lossy-network simulator + convergence fuzz (`src/replica.mojo`, `src/sim.mojo`, `tests/test_sync.mojo`)
- **Win:** generics over a trait (`Replica[S: Storage]`, `Cluster[S]`) compose well; the same fuzz function runs against `MemoryStorage` and the Python-backed `TinyStorage` unchanged.
- **Win:** 40 seeds x 3 replicas x 120 steps with +/-10 s clock skew, 25% loss, duplicates, delays and reordering all converge to the LWW oracle. Mutation check (break LWW compare) is caught by the fuzz and echo tests, so the tests have teeth.
- **Friction:** a `struct` field of generic trait type needed the trait to include `Deinitable` (error: "field 'store' has non-'Deinitable' type 'S'"); `Movable` alone isn't enough. Not obvious from the error.
- **Friction:** can't hold `&mut` to two `List` elements at once (aliasing), so replicas exchange owned `Batch` values rather than calling each other; ended up a cleaner design anyway.
- **Friction:** no ternary-free `String` joins/`split` returns `StringSpan` requiring `String(...)` wrapping; no stdlib RNG used (wrote xorshift for determinism).
- **Perf note:** TinyDB's whole-file JSON model + Python interop is the slow part of the TinyDB fuzz; memory backend is ~4x faster for the same work (wall time, ignoring the broken test timer).
