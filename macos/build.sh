#!/bin/bash
set -e

IMAGE="nvidia/cuda:12.1.0-devel-ubuntu22.04"
PROJECT_ROOT="$(pwd)"
SQLITE_SRC="$PROJECT_ROOT/sqlite"
BUILD_DIR="$PROJECT_ROOT/build"

mkdir -p "$BUILD_DIR"

docker run --rm \
    --platform linux/amd64 \
    -v "$SQLITE_SRC":/sqlite:ro \
    -v "$BUILD_DIR":/build \
    -w /build \
    "$IMAGE" \
    /bin/bash -c "
        if [ ! -f Makefile ]; then
            /sqlite/configure && make sqlite3.c
        else
            make sqlite3.c
        fi

        gcc -O3 shell.c sqlite3.c \
            -I. -I/usr/local/cuda/include \
            -L/usr/local/cuda/lib64 \
            -lcudart -lpthread -ldl -lm \
            -o sqlite3
    "

if [ -f "$BUILD_DIR/sqlite3" ]; then
    echo "binary is at: $BUILD_DIR/sqlite3"
    file "$BUILD_DIR/sqlite3"
else
    echo "error in building sqlite3"
fi
