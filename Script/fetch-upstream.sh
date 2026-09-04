#!/bin/bash

# Clone the pinned upstream sources into build/src, at the exact commits
# Upstream.versions names.
# Usage: ./fetch-upstream.sh

set -e

cd "$(dirname "$0")/.."
if [ ! -f .root ]; then
    echo "[*] malformed project structure"
    exit 1
fi

source ./Upstream.versions

SRC_DIR="$(pwd)/build/src"
mkdir -p "$SRC_DIR"

fetch() {
    local name=$1 repo=$2 ref=$3
    local dir="$SRC_DIR/$name"

    if [ ! -d "$dir/.git" ]; then
        rm -rf "$dir"
        git init -q "$dir"
        git -C "$dir" remote add origin "$repo"
    fi

    if [ "$(git -C "$dir" rev-parse HEAD 2>/dev/null)" != "$ref" ]; then
        echo "[*] $name: fetching $ref"
        git -C "$dir" fetch --depth 1 origin "$ref" >/dev/null
        git -C "$dir" checkout -q --force FETCH_HEAD
    fi

    git -C "$dir" clean -qfdx
    git -C "$dir" reset -q --hard
    echo "[*] $name: $(git -C "$dir" rev-parse HEAD)"
}

fetch libarchive "$LIBARCHIVE_REPO" "$LIBARCHIVE_REF"
fetch xz "$XZ_REPO" "$XZ_REF"
fetch zstd "$ZSTD_REPO" "$ZSTD_REF"
fetch lz4 "$LZ4_REPO" "$LZ4_REF"

echo "[*] done $(basename "$0")"
