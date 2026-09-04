#!/bin/bash

# Build every variant of one platform group. Exists so CI can fan the work out
# across runners; build.sh calls it once per group.
# Usage: ./build-platform.sh <platform_group> <output_dir>
#        ./build-platform.sh --list
# Platform groups: macos, ios, tvos, watchos, visionos
#
# --list prints every variant, so merge-xcframework.sh can check its inputs
# against this table instead of keeping a second copy of it.

set -e

cd "$(dirname "$0")/.."
if [ ! -f .root ]; then
    echo "[*] malformed project structure"
    exit 1
fi

PLATFORM_GROUP=$1
OUTPUT_DIR=$2

variants_for_group() {
    case "$1" in
    macos) echo "macosx maccatalyst" ;;
    ios) echo "iphoneos iphonesimulator" ;;
    tvos) echo "appletvos appletvsimulator" ;;
    watchos) echo "watchos watchsimulator" ;;
    visionos) echo "xros xrsimulator" ;;
    *) return 1 ;;
    esac
}

ALL_GROUPS="macos ios tvos watchos visionos"

if [ "$PLATFORM_GROUP" = "--list" ]; then
    for group in $ALL_GROUPS; do
        variants_for_group "$group"
    done
    exit 0
fi

if [ -z "$PLATFORM_GROUP" ] || [ -z "$OUTPUT_DIR" ]; then
    echo "Usage: $0 <platform_group> <output_dir>"
    exit 1
fi

if ! VARIANTS=$(variants_for_group "$PLATFORM_GROUP"); then
    echo "[!] unknown platform group: $PLATFORM_GROUP"
    echo "Valid groups: $ALL_GROUPS"
    exit 1
fi

./Script/fetch-upstream.sh

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR=$(cd "$OUTPUT_DIR" && pwd)

for variant in $VARIANTS; do
    ./Script/build-variant.sh "$variant" "$OUTPUT_DIR"
done

echo "[*] build complete for $PLATFORM_GROUP"
echo "[*] output: $OUTPUT_DIR"
