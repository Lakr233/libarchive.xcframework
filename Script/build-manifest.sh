#!/bin/bash

# Render Package.swift from the template with the freshly built checksum.
# Usage: ./build-manifest.sh <xcframework_zip> <download_url>

set -e

cd "$(dirname "$0")/.."
if [ ! -f .root ]; then
    echo "[*] malformed project structure"
    exit 1
fi

XCFRAMEWORK_ZIP=$1
DOWNLOAD_URL=$2

if [ ! -f "$XCFRAMEWORK_ZIP" ]; then
    echo "[*] $XCFRAMEWORK_ZIP not found"
    exit 1
fi

CHECKSUM=$(shasum -a 256 "$XCFRAMEWORK_ZIP" | awk '{print $1}')

MANIFEST=$(cat Package.swift.template)
MANIFEST=${MANIFEST/__DOWNLOAD_URL__/$DOWNLOAD_URL}
MANIFEST=${MANIFEST/__CHECKSUM__/$CHECKSUM}

# Substituting a placeholder that is not there is silent, and a Package.swift
# still holding "__CHECKSUM__" parses fine -- swift package dump-package does
# not validate binary target checksums -- so CI would publish it.
if echo "$MANIFEST" | grep -q '__'; then
    echo "[!] Package.swift.template has a placeholder this script does not fill:"
    echo "$MANIFEST" | grep -n '__'
    exit 1
fi

echo "$MANIFEST" >Package.swift
cat Package.swift

echo "[*] done $(basename "$0")"
