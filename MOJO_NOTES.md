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
