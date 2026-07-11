#!/bin/bash
# Builds whisper.cpp as static libraries with Metal support and copies
# libs + public headers into vendor/whisper and Sources/CWhisper/include.
set -euo pipefail

WHISPER_TAG="v1.9.1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/vendor/whisper.cpp"
OUT="$ROOT/vendor/whisper"

if [ ! -d "$SRC" ]; then
    git clone --depth 1 --branch "$WHISPER_TAG" \
        https://github.com/ggml-org/whisper.cpp.git "$SRC"
fi

cmake -S "$SRC" -B "$SRC/build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DGGML_METAL=ON \
    -DGGML_METAL_EMBED_LIBRARY=ON \
    -DWHISPER_BUILD_TESTS=OFF \
    -DWHISPER_BUILD_EXAMPLES=OFF \
    -DWHISPER_BUILD_SERVER=OFF
cmake --build "$SRC/build" -j "$(sysctl -n hw.ncpu)"

mkdir -p "$OUT/lib" "$ROOT/Sources/CWhisper/include"
find "$SRC/build" -name '*.a' -exec cp {} "$OUT/lib/" \;
# Only C headers the module map can digest (ggml-cpp.h and exotic backends break it).
cp "$SRC/include/whisper.h" "$ROOT/Sources/CWhisper/include/"
for h in ggml.h ggml-alloc.h ggml-backend.h ggml-cpu.h ggml-metal.h ggml-blas.h gguf.h; do
    cp "$SRC/ggml/include/$h" "$ROOT/Sources/CWhisper/include/"
done

echo "Done. Libs:"
ls "$OUT/lib"
