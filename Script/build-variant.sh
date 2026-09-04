#!/bin/bash

# Build liblzma, libzstd and libarchive for one xcframework variant.
# Usage: ./build-variant.sh <variant> <output_dir>
#
# Produces, under <output_dir>/<variant>:
#   include/{archive.h,archive_entry.h,module.modulemap}
#   lib/libarchive.a   fat static archive, liblzma + libzstd merged in
#
# Everything here is static. Consumers that want a dynamic framework get it
# from the .dynamic product in Package.swift, which links this archive into a
# dylib SwiftPM builds itself.

set -e

cd "$(dirname "$0")/.."
if [ ! -f .root ]; then
    echo "[*] malformed project structure"
    exit 1
fi
ROOT_DIR=$(pwd)

VARIANT=$1
OUTPUT_DIR=$2

if [ -z "$VARIANT" ] || [ -z "$OUTPUT_DIR" ]; then
    echo "Usage: $0 <variant> <output_dir>"
    exit 1
fi

# CMake understands iOS/tvOS/watchOS/visionOS as system names and derives the
# right target triple from the sysroot. Mac Catalyst it does not know about, so
# that one is a macOS build with an explicit -target.
CATALYST_TARGET=""
case "$VARIANT" in
macosx)           SYSTEM_NAME=Darwin   SDK=macosx           ARCHS="x86_64 arm64"          MIN_VERSION=10.13 ;;
maccatalyst)      SYSTEM_NAME=Darwin   SDK=macosx           ARCHS="x86_64 arm64"          MIN_VERSION=""    CATALYST_TARGET=ios13.1-macabi ;;
iphoneos)         SYSTEM_NAME=iOS      SDK=iphoneos         ARCHS="arm64 arm64e"          MIN_VERSION=12.0 ;;
iphonesimulator)  SYSTEM_NAME=iOS      SDK=iphonesimulator  ARCHS="x86_64 arm64"          MIN_VERSION=12.0 ;;
appletvos)        SYSTEM_NAME=tvOS     SDK=appletvos        ARCHS="arm64"                 MIN_VERSION=12.0 ;;
appletvsimulator) SYSTEM_NAME=tvOS     SDK=appletvsimulator ARCHS="x86_64 arm64"          MIN_VERSION=12.0 ;;
# armv7k is dropped: current linkers refuse it ("ld: -arch armv7k is no longer
# supported"), and arm64_32 already covers every watch that can run watchOS 5.
watchos)          SYSTEM_NAME=watchOS  SDK=watchos          ARCHS="arm64_32 arm64"        MIN_VERSION=5.0 ;;
watchsimulator)   SYSTEM_NAME=watchOS  SDK=watchsimulator   ARCHS="x86_64 arm64"          MIN_VERSION=5.0 ;;
xros)             SYSTEM_NAME=visionOS SDK=xros             ARCHS="arm64"                 MIN_VERSION=1.0 ;;
xrsimulator)      SYSTEM_NAME=visionOS SDK=xrsimulator      ARCHS="arm64"                 MIN_VERSION=1.0 ;;
*)
    echo "[!] unknown variant: $VARIANT"
    exit 1
    ;;
esac

# The external-program filters are off on every platform. They shell out to a
# helper binary, which no sandboxed app can do, and fork/vfork/posix_spawn are
# marked unavailable on tvOS and watchOS anyway -- the CMake probes find them
# regardless and the build then fails on the first use. Turning them off
# uniformly keeps one library that behaves the same everywhere.
SPAWN_ARGS=(-DHAVE_FORK=0 -DHAVE_VFORK=0 -DHAVE_POSIX_SPAWNP=0)

SDKROOT=$(xcrun --sdk "$SDK" --show-sdk-path)

SRC_DIR="$ROOT_DIR/build/src"
for src in libarchive xz zstd lz4; do
    if [ ! -d "$SRC_DIR/$src" ]; then
        echo "[!] missing source: $SRC_DIR/$src (run Script/fetch-upstream.sh)"
        exit 1
    fi
done

if command -v ninja >/dev/null 2>&1; then
    GENERATOR=(-G Ninja)
else
    GENERATOR=(-G "Unix Makefiles")
fi

BEGIN_TIME=$(date +%s)
echo "========================================"
echo "[*] variant: $VARIANT"
echo "[*] system:  $SYSTEM_NAME"
echo "[*] sdk:     $SDK"
echo "[*] archs:   $ARCHS"
echo "[*] min:     ${MIN_VERSION:-$CATALYST_TARGET}"
echo "========================================"

WORK_DIR="$ROOT_DIR/build/work/$VARIANT"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

ARCH_PREFIXES=()

for ARCH in $ARCHS; do
    echo "----------------------------------------"
    echo "==> $VARIANT $ARCH"
    echo "----------------------------------------"

    PREFIX="$WORK_DIR/$ARCH"
    rm -rf "$PREFIX"
    mkdir -p "$PREFIX"

    EXTRA_C_FLAGS=""
    if [ -n "$CATALYST_TARGET" ]; then
        EXTRA_C_FLAGS="-target $ARCH-apple-$CATALYST_TARGET -Wno-overriding-option"
    fi

    COMMON_ARGS=(
        "${GENERATOR[@]}"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_SYSTEM_NAME="$SYSTEM_NAME"
        -DCMAKE_OSX_SYSROOT="$SDK"
        -DCMAKE_OSX_ARCHITECTURES="$ARCH"
        -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN_VERSION"
        -DCMAKE_C_FLAGS="$EXTRA_C_FLAGS"
        -DCMAKE_INSTALL_PREFIX="$PREFIX"
        -DCMAKE_POLICY_VERSION_MINIMUM=3.10
    )

    # liblzma: .tar.xz, .lzma and the LZMA-compressed 7-Zip variants.
    cmake -S "$SRC_DIR/xz" -B "$WORK_DIR/build-xz-$ARCH" "${COMMON_ARGS[@]}" \
        -DBUILD_SHARED_LIBS=OFF \
        -DCMAKE_C_VISIBILITY_PRESET=hidden \
        -DXZ_NLS=OFF \
        -DXZ_DOC=OFF \
        -DXZ_TOOL_XZ=OFF \
        -DXZ_TOOL_XZDEC=OFF \
        -DXZ_TOOL_LZMADEC=OFF \
        -DXZ_TOOL_LZMAINFO=OFF \
        -DXZ_TOOL_SCRIPTS=OFF \
        -DBUILD_TESTING=OFF >/dev/null
    cmake --build "$WORK_DIR/build-xz-$ARCH" --target install >/dev/null

    # libzstd: .tar.zst and Zstandard-compressed zip entries.
    cmake -S "$SRC_DIR/zstd/build/cmake" -B "$WORK_DIR/build-zstd-$ARCH" "${COMMON_ARGS[@]}" \
        -DCMAKE_C_VISIBILITY_PRESET=hidden \
        -DZSTD_BUILD_STATIC=ON \
        -DZSTD_BUILD_SHARED=OFF \
        -DZSTD_BUILD_PROGRAMS=OFF \
        -DZSTD_BUILD_TESTS=OFF \
        -DZSTD_LEGACY_SUPPORT=OFF \
        -DZSTD_MULTITHREAD_SUPPORT=OFF \
        -DBUILD_TESTING=OFF >/dev/null
    cmake --build "$WORK_DIR/build-zstd-$ARCH" --target install >/dev/null

    # liblz4: .tar.lz4 and LZ4-compressed zip entries. Its headers force
    # default visibility on every entry point, so -fvisibility=hidden alone
    # would not keep LZ4_* out of the exported symbol table the way it does for
    # xz and zstd; blanking the two visibility macros is the escape hatch lz4
    # documents for exactly this.
    cmake -S "$SRC_DIR/lz4/build/cmake" -B "$WORK_DIR/build-lz4-$ARCH" "${COMMON_ARGS[@]}" \
        -DCMAKE_C_FLAGS="$EXTRA_C_FLAGS -DLZ4LIB_VISIBILITY= -DLZ4FLIB_VISIBILITY=" \
        -DCMAKE_C_VISIBILITY_PRESET=hidden \
        -DBUILD_SHARED_LIBS=OFF \
        -DBUILD_STATIC_LIBS=ON \
        -DLZ4_BUILD_CLI=OFF \
        -DLZ4_BUILD_LEGACY_LZ4C=OFF \
        -DBUILD_TESTING=OFF >/dev/null
    cmake --build "$WORK_DIR/build-lz4-$ARCH" --target install >/dev/null

    LIBARCHIVE_ARGS=(
        "${COMMON_ARGS[@]}"
        "${SPAWN_ARGS[@]}"
        -DENABLE_TEST=OFF
        -DENABLE_TAR=OFF
        -DENABLE_CPIO=OFF
        -DENABLE_CAT=OFF
        -DENABLE_UNZIP=OFF
        # CommonCrypto covers every digest libarchive wants, so OpenSSL,
        # mbedTLS and Nettle would only add weight. libb2 likewise: libarchive
        # carries its own BLAKE2. liblzo2 is the one codec left out on licence
        # grounds -- it is GPLv2, everything vendored here is BSD or 0BSD.
        # PCRE only feeds bsdtar and bsdcpio, which this build does not produce.
        -DENABLE_OPENSSL=OFF
        -DENABLE_LIBB2=OFF
        -DENABLE_LZO=OFF
        -DENABLE_EXPAT=OFF
        -DENABLE_PCREPOSIX=OFF
        -DENABLE_PCRE2POSIX=OFF
        -DENABLE_LIBGCC=OFF
        # Point at the libraries just installed. Letting find_package look for
        # them would search the host, which on a Mac with Homebrew means a macOS
        # liblzma quietly getting picked for an iOS build.
        -DLIBLZMA_INCLUDE_DIR="$PREFIX/include"
        -DLIBLZMA_LIBRARY="$PREFIX/lib/liblzma.a"
        -DZSTD_INCLUDE_DIR="$PREFIX/include"
        -DZSTD_LIBRARY="$PREFIX/lib/libzstd.a"
        -DLZ4_INCLUDE_DIR="$PREFIX/include"
        -DLZ4_LIBRARY="$PREFIX/lib/liblz4.a"
        # libxml2 is the one optional dependency that ships headers in the SDKs,
        # so it comes from there rather than being vendored. It is what turns on
        # xar, for writing as well as reading.
        -DLIBXML2_INCLUDE_DIR="$SDKROOT/usr/include/libxml2"
        -DLIBXML2_LIBRARY="$SDKROOT/usr/lib/libxml2.tbd"
        # libarchive only probes CommonCrypto when CMAKE_SYSTEM_NAME is
        # "Darwin", so every non-macOS Apple platform would otherwise end up
        # with no digest backend at all -- no mtree hashes, no encrypted zip.
        -DARCHIVE_CRYPTO_MD5=1 -DARCHIVE_CRYPTO_MD5_LIBSYSTEM=1
        -DARCHIVE_CRYPTO_SHA1=1 -DARCHIVE_CRYPTO_SHA1_LIBSYSTEM=1
        -DARCHIVE_CRYPTO_SHA256=1 -DARCHIVE_CRYPTO_SHA256_LIBSYSTEM=1
        -DARCHIVE_CRYPTO_SHA384=1 -DARCHIVE_CRYPTO_SHA384_LIBSYSTEM=1
        -DARCHIVE_CRYPTO_SHA512=1 -DARCHIVE_CRYPTO_SHA512_LIBSYSTEM=1
    )

    echo "[*] building libarchive"
    cmake -S "$SRC_DIR/libarchive" -B "$WORK_DIR/build-libarchive-$ARCH" \
        "${LIBARCHIVE_ARGS[@]}" -DBUILD_SHARED_LIBS=OFF >/dev/null
    cmake --build "$WORK_DIR/build-libarchive-$ARCH" --target install >/dev/null

    # Replaces the fork helpers libarchive drops along with the external-program
    # filters, which its program-filter sources reference either way.
    cmake -S "$ROOT_DIR/Vendor" -B "$WORK_DIR/build-stub-$ARCH" "${COMMON_ARGS[@]}" >/dev/null
    cmake --build "$WORK_DIR/build-stub-$ARCH" --target install >/dev/null

    # One archive per slice: libarchive's own objects plus the two bundled
    # dependencies, so a consumer links a single -larchive and nothing else.
    echo "[*] merging static libraries"
    libtool -static -o "$PREFIX/lib/libarchive-merged.a" \
        "$PREFIX/lib/libarchive.a" \
        "$PREFIX/lib/liblzma.a" \
        "$PREFIX/lib/libzstd.a" \
        "$PREFIX/lib/liblz4.a" \
        "$PREFIX/lib/libarchive_filter_fork_stub.a" 2>/dev/null
    mv "$PREFIX/lib/libarchive-merged.a" "$PREFIX/lib/libarchive.a"

    ARCH_PREFIXES+=("$PREFIX")
done

DEST="$OUTPUT_DIR/$VARIANT"
rm -rf "$DEST"
mkdir -p "$DEST/lib" "$DEST/include"

echo "[*] creating fat binary in $DEST"
LIPO_INPUTS=()
for PREFIX in "${ARCH_PREFIXES[@]}"; do
    LIPO_INPUTS+=("$PREFIX/lib/libarchive.a")
done
lipo -create "${LIPO_INPUTS[@]}" -output "$DEST/lib/libarchive.a"
lipo -info "$DEST/lib/libarchive.a"

cp "${ARCH_PREFIXES[0]}/include/archive.h" "$DEST/include/archive.h"
cp "${ARCH_PREFIXES[0]}/include/archive_entry.h" "$DEST/include/archive_entry.h"

cat >"$DEST/include/module.modulemap" <<'EOF'
module libarchive {
    header "archive.h"
    header "archive_entry.h"
    export *
}
EOF

rm -rf "$WORK_DIR"

ELAPSED_TIME=$(($(date +%s) - BEGIN_TIME))
echo "[*] $VARIANT finished in ${ELAPSED_TIME}s"
