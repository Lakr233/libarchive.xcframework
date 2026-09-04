#!/bin/bash

# Merge the per-variant artifacts into libarchive.xcframework.
# Usage: ./merge-xcframework.sh <artifacts_dir> <output_zip>

set -e

cd "$(dirname "$0")/.."
if [ ! -f .root ]; then
    echo "[*] malformed project structure"
    exit 1
fi
ROOT_DIR=$(pwd)

source ./Upstream.versions

ARTIFACTS_DIR=$1
OUTPUT_ZIP=$2

if [ -z "$ARTIFACTS_DIR" ] || [ -z "$OUTPUT_ZIP" ]; then
    echo "Usage: $0 <artifacts_dir> <output_zip>"
    exit 1
fi

ARTIFACTS_DIR=$(cd "$ARTIFACTS_DIR" && pwd)
mkdir -p "$(dirname "$OUTPUT_ZIP")"

FRAMEWORK_NAME="libarchive"
BUNDLE_ID="wiki.qaq.libarchive-xcframework.libarchive"
STAGE_DIR="$ROOT_DIR/build/framework-staging"
XCFRAMEWORK_PATH="$ROOT_DIR/build/$FRAMEWORK_NAME.xcframework"
REQUIRED_VARIANTS=$(./Script/build-platform.sh --list | tr '\n' ' ')

for variant in $REQUIRED_VARIANTS; do
    if [ ! -f "$ARTIFACTS_DIR/$variant/lib/libarchive.a" ]; then
        echo "[!] missing variant: $variant"
        exit 1
    fi
    echo "[*] found variant: $variant"
done

plist_platform_for_variant() {
    case "$1" in
    macosx | maccatalyst) echo "MacOSX" ;;
    iphoneos) echo "iPhoneOS" ;;
    iphonesimulator) echo "iPhoneSimulator" ;;
    appletvos) echo "AppleTVOS" ;;
    appletvsimulator) echo "AppleTVSimulator" ;;
    watchos) echo "WatchOS" ;;
    watchsimulator) echo "WatchSimulator" ;;
    xros) echo "XROS" ;;
    xrsimulator) echo "XRSimulator" ;;
    *)
        echo "[!] unknown variant: $1" >&2
        exit 1
        ;;
    esac
}

# Two spellings appear side by side: the current LC_BUILD_VERSION carries
# "minos", while slices the toolchain still emits the old way carry
# LC_VERSION_MIN_* and "version". Read whichever the object has.
load_command_min_versions() {
    otool -l "$1" 2>/dev/null |
        awk '
            /^ *cmd LC_BUILD_VERSION$/ { want = "minos"; next }
            /^ *cmd LC_VERSION_MIN_/ { want = "version"; next }
            want == "minos" && /^ *minos / { print $2; want = ""; next }
            want == "version" && /^ *version / { print $2; want = ""; next }
        '
}

# The lowest OS the staged library was built for, read from its own load
# commands. Taking it from the binary rather than repeating the numbers in
# build-variant.sh keeps the two from drifting: the toolchain raises the floor
# on its own -- arm64 macOS starts at 11.0 where the build asks for 10.13, and
# arm64e starts at iOS 14.0 where it asks for 12.0.
#
# Every slice is thinned out first: otool reports only one architecture of a fat
# archive whose slices share a cpu type, which is exactly the arm64/arm64e case
# above, and reading only that one would claim a floor two releases too high.
minimum_os_version_for_library() {
    local library_path="$1"
    local archs arch temp_dir

    archs=$(lipo -archs "$library_path" 2>/dev/null || true)
    if [ -z "$archs" ]; then
        load_command_min_versions "$library_path" | sort -uV | head -n 1
        return
    fi

    temp_dir=$(mktemp -d)
    for arch in $archs; do
        lipo -thin "$arch" -output "$temp_dir/slice.a" "$library_path" 2>/dev/null ||
            cp "$library_path" "$temp_dir/slice.a"
        load_command_min_versions "$temp_dir/slice.a"
    done | sort -uV | head -n 1
    rm -rf "$temp_dir"
}

# macOS frameworks use the versioned "deep" layout; everything else, Mac
# Catalyst included, uses the flat one.
version_framework_for_variant() {
    local variant="$1"
    local framework_path="$2"
    local version_dir="$framework_path/Versions/A"

    case "$variant" in
    macosx | maccatalyst) ;;
    *) return 0 ;;
    esac

    mkdir -p "$version_dir/Resources"
    mv "$framework_path/$FRAMEWORK_NAME" "$version_dir/$FRAMEWORK_NAME"
    mv "$framework_path/Headers" "$version_dir/Headers"
    mv "$framework_path/Modules" "$version_dir/Modules"
    mv "$framework_path/Info.plist" "$version_dir/Resources/Info.plist"

    ln -s A "$framework_path/Versions/Current"
    ln -s "Versions/Current/$FRAMEWORK_NAME" "$framework_path/$FRAMEWORK_NAME"
    ln -s Versions/Current/Headers "$framework_path/Headers"
    ln -s Versions/Current/Modules "$framework_path/Modules"
    ln -s Versions/Current/Resources "$framework_path/Resources"
}

verify_deep_framework_layout() {
    local xcframework_path="$1"
    local framework_path

    while IFS= read -r -d '' framework_path; do
        if [ ! -L "$framework_path/$FRAMEWORK_NAME" ] ||
            [ ! -L "$framework_path/Headers" ] ||
            [ ! -L "$framework_path/Modules" ] ||
            [ ! -L "$framework_path/Resources" ] ||
            [ ! -L "$framework_path/Versions/Current" ] ||
            [ ! -f "$framework_path/Versions/A/Resources/Info.plist" ]; then
            echo "[!] invalid deep framework layout: $framework_path"
            exit 1
        fi
    done < <(find "$xcframework_path" \( -path "*/macos-*/$FRAMEWORK_NAME.framework" -o -path "*-maccatalyst/$FRAMEWORK_NAME.framework" \) -type d -print0)
}

verify_xcframework_zip() {
    local zip_path="$1"
    local unpack_dir

    unpack_dir=$(mktemp -d)
    ditto -x -k "$zip_path" "$unpack_dir"
    verify_deep_framework_layout "$unpack_dir/$FRAMEWORK_NAME.xcframework"
    rm -rf "$unpack_dir"
}

stage_framework() {
    local variant="$1"
    local library_path="$ARTIFACTS_DIR/$variant/lib/libarchive.a"
    local header_dir="$ARTIFACTS_DIR/$variant/include"
    local framework_path="$STAGE_DIR/$variant/$FRAMEWORK_NAME.framework"
    local platform
    local minimum_os_version
    local minimum_version_key

    platform=$(plist_platform_for_variant "$variant")
    minimum_os_version=$(minimum_os_version_for_library "$library_path")
    if [ -z "$minimum_os_version" ]; then
        echo "[!] could not read a minimum OS version from: $library_path" >&2
        exit 1
    fi

    # macOS bundles declare their floor as LSMinimumSystemVersion; every other
    # platform, Mac Catalyst included, uses MinimumOSVersion. An app that ships
    # a framework without it is rejected by App Store validation with
    # ITMS-90360 and ITMS-90530.
    case "$variant" in
    macosx) minimum_version_key="LSMinimumSystemVersion" ;;
    *) minimum_version_key="MinimumOSVersion" ;;
    esac

    rm -rf "$framework_path"
    mkdir -p "$framework_path/Headers" "$framework_path/Modules"
    cp "$library_path" "$framework_path/$FRAMEWORK_NAME"
    cp "$header_dir/archive.h" "$header_dir/archive_entry.h" "$framework_path/Headers/"
    sed 's/^module /framework module /' "$header_dir/module.modulemap" \
        >"$framework_path/Modules/module.modulemap"

    cat >"$framework_path/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$FRAMEWORK_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$FRAMEWORK_NAME</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>$LIBARCHIVE_VERSION</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>$platform</string>
    </array>
    <key>CFBundleVersion</key>
    <string>$LIBARCHIVE_VERSION</string>
    <key>$minimum_version_key</key>
    <string>$minimum_os_version</string>
</dict>
</plist>
EOF

    version_framework_for_variant "$variant" "$framework_path"
}

rm -rf "$STAGE_DIR" "$XCFRAMEWORK_PATH" "$OUTPUT_ZIP"

XCFRAMEWORK_COMMAND=()
for variant in $REQUIRED_VARIANTS; do
    echo "[*] staging $variant"
    stage_framework "$variant"
    XCFRAMEWORK_COMMAND+=("-framework" "$STAGE_DIR/$variant/$FRAMEWORK_NAME.framework")
done

echo "[*] creating xcframework"
xcodebuild -create-xcframework -output "$XCFRAMEWORK_PATH" "${XCFRAMEWORK_COMMAND[@]}"
verify_deep_framework_layout "$XCFRAMEWORK_PATH"

echo "[*] packing with ditto (preserve symlinks)"
pushd "$(dirname "$XCFRAMEWORK_PATH")" >/dev/null
ditto -c -k --sequesterRsrc --keepParent "$FRAMEWORK_NAME.xcframework" "$FRAMEWORK_NAME.xcframework.zip"
popd >/dev/null

verify_xcframework_zip "$(dirname "$XCFRAMEWORK_PATH")/$FRAMEWORK_NAME.xcframework.zip"

mv "$(dirname "$XCFRAMEWORK_PATH")/$FRAMEWORK_NAME.xcframework.zip" "$OUTPUT_ZIP"

# Keep the unzipped copy around: Package.swift picks it up over the released
# one, so the Example app and `swift test` exercise what was just built.
mkdir -p "$ROOT_DIR/BinaryTarget"
rm -rf "$ROOT_DIR/BinaryTarget/$FRAMEWORK_NAME.xcframework"
mv "$XCFRAMEWORK_PATH" "$ROOT_DIR/BinaryTarget/$FRAMEWORK_NAME.xcframework"
rm -rf "$STAGE_DIR"

echo "[*] xcframework created: $OUTPUT_ZIP"
echo "[*] done $(basename "$0")"
