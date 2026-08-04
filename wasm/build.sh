#!/bin/sh
# Build the WebAssembly bundle that docs/index.html loads.
#
# One .wasm serves both columns of the comparison page: the page calls
# tolerant_render twice with different options bitmasks, so strict and tolerant
# output always come from the same binary and cannot drift apart.
#
# Requires emsdk on PATH:
#   . /path/to/emsdk/emsdk_env.sh
set -eu

cd "$(dirname "$0")/.."

command -v emcc >/dev/null 2>&1 || {
  echo "emcc not found. Activate emsdk first:" >&2
  echo "  . /path/to/emsdk/emsdk_env.sh" >&2
  exit 2
}

BUILD=wasm/build

emcmake cmake -S . -B "$BUILD" \
  -DCMARK_TESTS=OFF \
  -DCMARK_SHARED=OFF \
  -DCMARK_STATIC=ON \
  -DCMARK_LIB_FUZZER=OFF \
  -DCMAKE_BUILD_TYPE=Release >/dev/null

emmake cmake --build "$BUILD" -j8 >/dev/null

emcc wasm/shim.c \
  "$BUILD/src/libcmark-gfm.a" \
  "$BUILD/extensions/libcmark-gfm-extensions.a" \
  -I src -I extensions -I "$BUILD/src" \
  -O2 \
  -sMODULARIZE=1 \
  -sEXPORT_NAME=CmarkGfm \
  -sALLOW_MEMORY_GROWTH=1 \
  -sEXPORTED_FUNCTIONS='["_tolerant_render","_tolerant_version","_free","_malloc"]' \
  -sEXPORTED_RUNTIME_METHODS='["cwrap","UTF8ToString","stringToNewUTF8"]' \
  -o docs/cmark-gfm.js

echo "built docs/cmark-gfm.js and docs/cmark-gfm.wasm"
ls -lh docs/cmark-gfm.js docs/cmark-gfm.wasm
