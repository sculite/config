#!/usr/bin/env bash
set -euo pipefail

# Build SQLite + CUDA GPU scan support inside an nvidia/cuda:*devel* container.
# Expected mounts:
#   /sqlite  -> SQLite source tree (read-only is fine)
#   /out     -> output build directory (read-write)

SQLITE_SRC_DIR="${SQLITE_SRC_DIR:-/sqlite}"
OUT_DIR="${OUT_DIR:-/out}"

# Optional customization
CUDA_ARCH="${CUDA_ARCH:-}"
NVCC_FLAGS="${NVCC_FLAGS:-}"  # e.g. "-lineinfo"
CC_FLAGS="${CC_FLAGS:-}"      # e.g. "-g"

# Default GPU sources (relative to SQLite source root)
DEFAULT_CUDA_SOURCES=("src/gpu_where.cu")
DEFAULT_GPU_C_SOURCES=("src/gpu_manager.c")
DEFAULT_GPU_HEADERS=("src/gpu_manager.h" "src/gpu_config.h")

# Override/extend via env vars (space-separated, relative to SQLite src root)
# Example:
#   CUDA_SOURCES="src/gpu_where.cu src/another_kernel.cu" ./build_gpu_in_container.sh
CUDA_SOURCES_STR="${CUDA_SOURCES:-}"
GPU_C_SOURCES_STR="${GPU_C_SOURCES:-}"
GPU_HEADERS_STR="${GPU_HEADERS:-}"

SQLITE_DEFINES=(
  "-DSQLITE_THREADSAFE=1"
  "-DSQLITE_ENABLE_COLUMN_METADATA=1"
  "-DSQLITE_ENABLE_FTS5=1"
  "-DSQLITE_ENABLE_GPU_SCAN=1"
  "-DSQLITE_OMIT_GPU=0"
  "-DNDEBUG"
)

CUDA_INCLUDE=("-I/usr/local/cuda/include")

if [[ -n "$CUDA_ARCH" ]]; then
  NVCC_ARCH_FLAGS=("-arch=${CUDA_ARCH}")
else
  NVCC_ARCH_FLAGS=()
fi

require_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "ERROR: required file not found: $path" >&2
    exit 1
  fi
}

# Build in a writable copy of the sqlite source (configure/make writes files)
WORK_ROOT="${WORK_ROOT:-/tmp/sqlite-gpu-build}"
SRC_COPY="$WORK_ROOT/sqlite"

rm -rf "$SRC_COPY"
mkdir -p "$WORK_ROOT" "$OUT_DIR"
cp -a "$SQLITE_SRC_DIR" "$SRC_COPY"

cd "$SRC_COPY"

if [[ ! -x "./configure" ]]; then
  echo "ERROR: ./configure not found in $SRC_COPY" >&2
  exit 1
fi

# Step 1: generate amalgamation
if [[ ! -f "Makefile" ]]; then
  ./configure >/dev/null
fi

make -s sqlite3.c sqlite3.h

require_file "$SRC_COPY/sqlite3.c"
require_file "$SRC_COPY/sqlite3.h"
require_file "$SRC_COPY/shell.c"

# Step 2: stage sources into OUT_DIR (so build outputs are on the mounted volume)
cp -f "$SRC_COPY/sqlite3.c" "$OUT_DIR/sqlite3.c"
cp -f "$SRC_COPY/sqlite3.h" "$OUT_DIR/sqlite3.h"
cp -f "$SRC_COPY/sqlite3ext.h" "$OUT_DIR/sqlite3ext.h"
cp -f "$SRC_COPY/shell.c" "$OUT_DIR/shell.c"

# Resolve GPU file lists
read -r -a CUDA_SOURCES <<<"$CUDA_SOURCES_STR"
read -r -a GPU_C_SOURCES <<<"$GPU_C_SOURCES_STR"
read -r -a GPU_HEADERS <<<"$GPU_HEADERS_STR"

if [[ ${#CUDA_SOURCES[@]} -eq 0 ]]; then
  CUDA_SOURCES=("${DEFAULT_CUDA_SOURCES[@]}")
fi
if [[ ${#GPU_C_SOURCES[@]} -eq 0 ]]; then
  GPU_C_SOURCES=("${DEFAULT_GPU_C_SOURCES[@]}")
fi
if [[ ${#GPU_HEADERS[@]} -eq 0 ]]; then
  GPU_HEADERS=("${DEFAULT_GPU_HEADERS[@]}")
fi

# Copy GPU files (flatten to OUT_DIR like the Windows script)
for rel in "${CUDA_SOURCES[@]}" "${GPU_C_SOURCES[@]}" "${GPU_HEADERS[@]}"; do
  src="$SRC_COPY/$rel"
  require_file "$src"
  cp -f "$src" "$OUT_DIR/$(basename "$rel")"
done

cd "$OUT_DIR"

# Step 3: compile CUDA kernels
CUDA_OBJS=()
for rel in "${CUDA_SOURCES[@]}"; do
  base="$(basename "$rel")"
  obj="${base%.cu}.o"
  require_file "$base"
  nvcc -O2 "${NVCC_ARCH_FLAGS[@]}" $NVCC_FLAGS -c "$base" -o "$obj"
  CUDA_OBJS+=("$obj")
done

# Step 4: compile GPU manager C sources
GPU_C_OBJS=()
for rel in "${GPU_C_SOURCES[@]}"; do
  base="$(basename "$rel")"
  obj="${base%.c}.o"
  require_file "$base"
  gcc -O2 $CC_FLAGS "${SQLITE_DEFINES[@]}" -I. "${CUDA_INCLUDE[@]}" -c "$base" -o "$obj"
  GPU_C_OBJS+=("$obj")
done

# Step 5: compile SQLite core with GPU support

gcc -O2 $CC_FLAGS "${SQLITE_DEFINES[@]}" -I. "${CUDA_INCLUDE[@]}" -c sqlite3.c -o sqlite3.o

# Step 6: compile shell and link final executable

gcc -O2 $CC_FLAGS "${SQLITE_DEFINES[@]}" -I. "${CUDA_INCLUDE[@]}" -c shell.c -o shell.o

# Use nvcc as the linker driver so CUDA link flags are handled consistently
nvcc -O2 "${NVCC_ARCH_FLAGS[@]}" -o sqlite3 \
  shell.o sqlite3.o "${GPU_C_OBJS[@]}" "${CUDA_OBJS[@]}" \
  -L/usr/local/cuda/lib64 -lcudart \
  -lpthread -ldl -lm

echo "Built: $OUT_DIR/sqlite3"
