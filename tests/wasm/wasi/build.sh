#!/bin/sh
# Rebuilds the WASI probes beside their sources (needs clang with a WASI sysroot, and wabt).
set -e
cd "$(dirname "$0")"
CLANG=${CLANG:-$(command -v /opt/homebrew/opt/llvm/bin/clang || command -v clang)}
SYSROOT=${WASI_SYSROOT:-/opt/homebrew/share/wasi-sysroot}
"$CLANG" --target=wasm32-wasip1 --sysroot="$SYSROOT" -O2 -Wall probe.c -o probe.wasm
for w in start badimport goodimport; do wat2wasm "$w.wat" -o "$w.wasm"; done
