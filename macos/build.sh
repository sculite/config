#!/usr/bin/env bash
set -euo pipefail

# IMAGE="${IMAGE:-nvidia/cuda:12.1.0-devel-ubuntu22.04}"
IMAGE="cuda-12:latest"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQLITE_SRC="${SQLITE_SRC:-$PROJECT_ROOT/sqlite}"
SCRIPTS_DIR="$PROJECT_ROOT/scripts"

# Mirrors sqlite/build_gpu.bat behavior.
OUT_DIR="${OUT_DIR:-$PROJECT_ROOT/build_gpu}"
mkdir -p "$OUT_DIR"

docker run --rm \
    --platform linux/amd64 \
    -v "$SQLITE_SRC":/sqlite:ro \
    -v "$OUT_DIR":/out \
    -v "$SCRIPTS_DIR":/scripts:ro \
    -w /out \
    "$IMAGE" \
    /bin/bash /scripts/build_gpu_in_container.sh

if [ -f "$OUT_DIR/sqlite3" ]; then
    echo "binary is at: $OUT_DIR/sqlite3"
    file "$OUT_DIR/sqlite3"
else
    echo "error building sqlite3"
    exit 1
fi
