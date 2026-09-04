#!/bin/bash

# Release tag helpers, read against the origin remote so answers match GitHub.
#
#   ./Script/next-tag.sh upstream [ref]   upstream.<short ref>.<rev>, rev = highest existing + 1
#                                         (ref defaults to LIBARCHIVE_REF in Upstream.versions)
#   ./Script/next-tag.sh exists <tag>     exit 0 if the tag exists on origin, 1 if not
#   ./Script/next-tag.sh package          <major>.<minor>.<patch + 1> of the highest package tag,
#                                         or 0.1.0 when none has been published yet
#
# Any other exit status means origin could not be listed; callers must not read
# that as "no".

set -euo pipefail

cd "$(dirname "$0")/.."
if [ ! -f .root ]; then
    echo "[!] Repository root not found. Run this from a full checkout." >&2
    exit 1
fi

# shellcheck disable=SC1091
source ./Upstream.versions

SHORT_REF_LENGTH=12

remote_tags() {
    git ls-remote --tags --refs origin | sed 's|.*refs/tags/||'
}

short_ref() {
    if ! echo "$1" | grep -Eq '^[0-9a-f]{40}$'; then
        echo "[!] Ref must be a full 40-character lowercase commit hash. Received: $1" >&2
        exit 1
    fi
    echo "${1:0:$SHORT_REF_LENGTH}"
}

case "${1:-}" in
upstream)
    ref=$(short_ref "${2:-$LIBARCHIVE_REF}")
    prefix="upstream.$ref."
    pattern="^${prefix//./\\.}[0-9]+$"
    last=$(remote_tags | { grep -E "$pattern" || true; } | sed "s|^$prefix||" | sort -n | tail -1)
    echo "$prefix$((${last:-0} + 1))"
    ;;
exists)
    tag=${2:-}
    if [ -z "$tag" ]; then
        echo "Usage: $0 exists <tag>" >&2
        exit 1
    fi
    rc=0
    git ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null || rc=$?
    case "$rc" in
    0) exit 0 ;;
    2) exit 1 ;;
    *)
        echo "[!] Could not list tags on origin (git exited $rc). Check the network and try again." >&2
        exit "$rc"
        ;;
    esac
    ;;
package)
    last=$(remote_tags | { grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' || true; } | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)
    if [ -z "$last" ]; then
        echo "0.1.0"
        exit 0
    fi
    IFS=. read -r major minor patch <<<"$last"
    echo "$major.$minor.$((patch + 1))"
    ;;
*)
    echo "Usage: $0 upstream [ref] | exists <tag> | package" >&2
    exit 1
    ;;
esac
