#!/bin/bash

# Resolves each upstream version to the commit it should be built from.
#
#   ./Script/resolve-upstream.sh                 the pins in Upstream.versions
#   ./Script/resolve-upstream.sh latest          the newest release of all three
#   ./Script/resolve-upstream.sh latest --write  also rewrite the pins
#
# stdout is eval-able: <NAME>_VERSION and <NAME>_REF for each dependency.
# Everything else goes to stderr.

set -euo pipefail

cd "$(dirname "$0")/.."
if [ ! -f .root ]; then
    echo "[!] Repository root not found. Run this from a full checkout." >&2
    exit 1
fi

# shellcheck disable=SC1091
source ./Upstream.versions

REQUESTED=""
WRITE=0
for argument in "$@"; do
    case "$argument" in
    --write) WRITE=1 ;;
    *) REQUESTED=$argument ;;
    esac
done

# The releases/latest redirect is cheaper than the API, less rate-limited, and
# skips prereleases for us.
latest_version() {
    local repo=$1 url
    for _ in $(seq 1 10); do
        url=$(curl -s -L -o /dev/null -w "%{url_effective}" "${repo%.git}/releases/latest")
        if [[ "$url" == */tag/* ]]; then
            echo "${url##*/tag/}" | sed 's|^v||'
            return 0
        fi
        sleep 5
    done
    echo "[!] Could not resolve the latest release of $repo." >&2
    return 1
}

# Annotated tags list both the tag object and the peeled commit (^{}); the
# commit is what we want to build.
commit_for_version() {
    local repo=$1 version=$2 tags ref
    tags=$(git ls-remote --tags "$repo" "refs/tags/v$version" "refs/tags/v$version^{}")
    ref=$(echo "$tags" | awk -v t="refs/tags/v$version^{}" '$2 == t { print $1 }')
    if [ -z "$ref" ]; then
        ref=$(echo "$tags" | awk -v t="refs/tags/v$version" '$2 == t { print $1 }')
    fi
    if [ -z "$ref" ]; then
        echo "[!] v$version was not found on $repo." >&2
        return 1
    fi
    echo "$ref"
}

resolve() {
    local name=$1 repo=$2 version=$3 ref=$4

    if [ "$REQUESTED" = "latest" ]; then
        version=$(latest_version "$repo")
        ref=$(commit_for_version "$repo" "$version")
    fi

    echo "${name}_VERSION=$version"
    echo "${name}_REF=$ref"

    if [ "$WRITE" -eq 1 ]; then
        # Only the two pin lines change; the file keeps its own comments.
        sed -e "s|^${name}_VERSION=.*|${name}_VERSION=$version|" \
            -e "s|^${name}_REF=.*|${name}_REF=$ref|" \
            Upstream.versions >Upstream.versions.tmp
        mv Upstream.versions.tmp Upstream.versions
        echo "[*] pinned $repo to $version ($ref)" >&2
    fi
}

if [ -n "$REQUESTED" ] && [ "$REQUESTED" != "latest" ]; then
    echo "[!] Only 'latest' is supported. Edit Upstream.versions by hand to pin a specific version." >&2
    exit 1
fi

resolve LIBARCHIVE "$LIBARCHIVE_REPO" "$LIBARCHIVE_VERSION" "$LIBARCHIVE_REF"
resolve XZ "$XZ_REPO" "$XZ_VERSION" "$XZ_REF"
resolve ZSTD "$ZSTD_REPO" "$ZSTD_VERSION" "$ZSTD_REF"
resolve LZ4 "$LZ4_REPO" "$LZ4_VERSION" "$LZ4_REF"
