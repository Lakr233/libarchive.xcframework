#!/bin/bash

# Full local build: every platform, the xcframework, refreshed Package.swift.
# Usage: ./build.sh [download_url]
#
# Releases come from CI, which fans the platform groups out across runners; this
# is the same pipeline in one process for working on the build itself.

set -e

cd "$(dirname "$0")/.."
if [ ! -f .root ]; then
    echo "[*] malformed project structure"
    exit 1
fi

source ./Upstream.versions

if [ -n "$1" ]; then
    DOWNLOAD_URL=$1
else
    REPO_SLUG=$(git config --get remote.origin.url 2>/dev/null |
        sed -E 's#(git@github.com:|https://github.com/|git://github.com/)([^/?]+/[^/.?]+)(\.git)?/?(\?.*)?$#\2#')
    if [ -z "$REPO_SLUG" ]; then
        REPO_SLUG="Lakr233/libarchive.xcframework"
        echo "[*] warning: no remote.origin.url, defaulting to $REPO_SLUG"
    fi
    # Not guarded: a failed ls-remote must not be read as "no tags yet", or the
    # manifest would name a storage tag that is already taken and holds a
    # different binary. The build clones three upstreams anyway, so being
    # offline is not a case worth degrading for.
    STORAGE_TAG=$(./Script/next-tag.sh upstream)
    DOWNLOAD_URL="https://github.com/$REPO_SLUG/releases/download/$STORAGE_TAG/libarchive.xcframework.zip"
fi

ARTIFACTS_DIR="$(pwd)/build/dest"
XCFRAMEWORK_ZIP="$(pwd)/build/libarchive.xcframework.zip"
rm -rf "$ARTIFACTS_DIR" "$XCFRAMEWORK_ZIP"
mkdir -p "$ARTIFACTS_DIR"

echo "[*] libarchive $LIBARCHIVE_VERSION, xz $XZ_VERSION, zstd $ZSTD_VERSION"
echo "[*] manifest download url: $DOWNLOAD_URL"

./Script/build-platform.sh macos "$ARTIFACTS_DIR"
./Script/build-platform.sh ios "$ARTIFACTS_DIR"
./Script/build-platform.sh tvos "$ARTIFACTS_DIR"
./Script/build-platform.sh watchos "$ARTIFACTS_DIR"
./Script/build-platform.sh visionos "$ARTIFACTS_DIR"

./Script/merge-xcframework.sh "$ARTIFACTS_DIR" "$XCFRAMEWORK_ZIP"
./Script/build-manifest.sh "$XCFRAMEWORK_ZIP" "$DOWNLOAD_URL"

echo "[*] done $(basename "$0")"
