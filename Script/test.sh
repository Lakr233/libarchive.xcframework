#!/bin/bash

# Build the package for every platform it claims to support.
# Usage: ./test.sh

cd "$(dirname "$0")/.."

SCHEME="LibArchive"

test_build() {
    DESTINATION=$1
    echo "[*] test build for $DESTINATION"
    xcodebuild -scheme $SCHEME -destination "$DESTINATION" | xcbeautify
    EXIT_CODE=${PIPESTATUS[0]}
    echo "[*] finished with exit code $EXIT_CODE"
    if [ "$EXIT_CODE" -ne 0 ]; then
        echo "[!] failed to build for $DESTINATION"
        exit 1
    fi
}

test_build "generic/platform=macOS"
test_build "generic/platform=macOS,variant=Mac Catalyst"
test_build "generic/platform=iOS"
test_build "generic/platform=iOS Simulator"
test_build "generic/platform=tvOS"
test_build "generic/platform=tvOS Simulator"
test_build "generic/platform=watchOS"
test_build "generic/platform=watchOS Simulator"
test_build "generic/platform=xrOS"
test_build "generic/platform=xrOS Simulator"

echo "[*] running unit tests on macOS"
swift test || exit 1

echo "[*] done $(basename "$0")"
