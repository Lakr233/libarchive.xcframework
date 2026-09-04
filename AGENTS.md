# AGENTS.md

Repackaging notes for [libarchive](https://github.com/libarchive/libarchive) as
a Swift package. `README.md` is for people consuming the package; this file is
for whoever changes how it is built.

## What this repo is

A build pipeline plus a thin Swift wrapper. There is no libarchive source here —
it is cloned at a pinned commit into `build/src` and compiled into one static
xcframework covering every Apple platform and architecture.

```
Upstream.versions          the pins: repo + version + 40-char commit for each dependency
Script/                    the whole build, one concern per script
Vendor/                    the only C we own: a two-function stub, see below
Sources/LibArchive/        @_exported import libarchive, plus the system link flags
Tests/LibArchiveTests/     round-trips that fail if a codec silently went missing
Example/ArchiveViewerApp/  a sandboxed iOS app that lists an archive's contents
Package.swift              GENERATED -- edit Package.swift.template instead
```

## The pipeline

```
fetch-upstream.sh      clone libarchive, xz, zstd, lz4 at their pinned commits
build-variant.sh       one xcframework variant: per-arch cmake builds, then lipo
build-platform.sh      the variants of one platform group (CI fans these out)
merge-xcframework.sh   stage a .framework per variant, xcodebuild -create-xcframework
build-manifest.sh      render Package.swift.template with the URL and checksum
build.sh               all of the above in one process, for working on the build
```

`build-variant.sh` owns every per-platform decision — SDK, architectures,
deployment target, CMake flags. It is the file to read first, and the only place
a new platform needs describing. `build-platform.sh --list` is the single source
of truth for which variants exist; `merge-xcframework.sh` asks it rather than
keeping a second copy.

## Things that will bite you

Each of these cost a debugging cycle. They are all commented at the site too.

**libarchive only probes CommonCrypto when `CMAKE_SYSTEM_NAME` is exactly
`Darwin`.** Every non-macOS Apple platform therefore ends up with *no* digest
backend — no mtree hashes, no encrypted zip — and configures happily while doing
it. `build-variant.sh` forces `ARCHIVE_CRYPTO_*_LIBSYSTEM` on instead.

**Turning off fork/vfork/posix_spawn does not remove the code that calls them.**
`archive_read_support_filter_program.c` references `__archive_create_child` and
`__archive_check_child` unconditionally, and `archive_read_support_filter_all`
pulls that object in through lzop/lrzip/grzip — so the library stops *linking*,
with no warning at build time. `Vendor/filter_fork_stub.c` supplies both
symbols; they fail the way a failed spawn already fails, which the callers
already handle. `testExternalProgramFilterFailsCleanly` pins that.

**`-fvisibility=hidden` is not enough for lz4.** Its headers annotate every
entry point with `visibility("default")` unless `LZ4LIB_VISIBILITY` and
`LZ4FLIB_VISIBILITY` are defined empty. xz and zstd need no such help. Check
with `nm -m`, not `nm -gU` — the latter prints `T` for private-external symbols
too, which reads as "still exported" when it is not.

**`otool -l` reports one architecture of a fat archive whose slices share a cpu
type.** That is exactly the arm64/arm64e case, so the minimum-OS probe in
`merge-xcframework.sh` thins each slice first. Reading the fat file directly
would have claimed iOS 14.0 where the build supports 12.0.

**armv7k no longer links** ("ld: -arch armv7k is no longer supported"). watchOS
is arm64_32 + arm64.

**Deployment targets are read back out of the built binary,** never written into
the `Info.plist` from the numbers in the build script. The toolchain raises the
floor on its own — arm64 macOS starts at 11.0 whatever you ask for.

## Dependencies

zlib, bzip2, iconv and libxml2 come from the SDKs, which ship headers for all
four; they are linked via `linkerSettings` in `Package.swift.template`. liblzma,
libzstd and liblz4 have no usable SDK copy and are compiled from source into the
same static archive, with hidden visibility so nothing leaks into an app's
symbol table.

The bar for adding another is a permissive licence. **liblzo2 is excluded
because it is GPLv2** — do not add it. OpenSSL, mbedTLS and Nettle are redundant
with CommonCrypto (and Nettle is LGPL), libb2 is redundant with libarchive's own
BLAKE2, and PCRE only feeds `bsdtar`/`bsdcpio`, which this package does not
build.

## Releases

Every published binary comes from the **Build libarchive** workflow. Do not
publish a locally built zip: the point of `upstream.<ref>.<rev>` is that the
binary is traceable to a commit and a CI run.

- `upstream.<12-char libarchive ref>.<rev>` holds `libarchive.xcframework.zip`.
  `<rev>` is the next free one, so rebuilding the same upstream after touching
  `Vendor/` or the scripts is normal and does not need a version bump.
- `<major>.<minor>.<patch>` is the package release consumers resolve. The
  workflow rewrites `Package.swift`, pushes it, then tags *that* commit.

`Script/next-tag.sh` computes both against `origin`. It exits non-zero when it
cannot reach the remote; never treat that as "no tags yet" — you would name a
tag that already exists and holds a different binary.

## Working locally

```bash
./Script/build.sh          # everything; ~45 min, leaves BinaryTarget/ in place
swift test                 # round-trips through every compiled-in codec
./Script/test.sh           # builds the package for all ten destinations
```

`build.sh` leaves the unzipped framework in `BinaryTarget/`, which
`Package.swift` prefers over the released URL, so `swift test` and the example
app exercise what you just built. SwiftPM caches the evaluated manifest on its
contents, not on the filesystem it looked at, so removing that directory is not
enough to go back to the released binary — `rm -rf BinaryTarget .build && swift
package purge-cache`.

To build one platform group while iterating:

```bash
./Script/build-platform.sh ios ./build/dest    # macos ios tvos watchos visionos
```

`build/src` is a cache of the pinned clones; deleting it only costs a re-clone.

## The example app

`Example/ArchiveViewerApp.xcodeproj` references the package by relative path, so
it always builds against the working tree. The target uses a
`PBXFileSystemSynchronizedRootGroup` — files added under
`Example/ArchiveViewerApp/` are picked up with no pbxproj edit.

It has to run with nothing outside its sandbox, which is why it writes its own
sample `.tar.xz` rather than shipping a fixture. The document picker accepts
`[.item]` on purpose: libarchive identifies formats by content, so filtering the
picker by extension would hide files it can actually read.

Xcode 27 has no standalone Simulator.app, so there is no way to script a tap.
Drive states from code when you need to screenshot a screen, and revert that
before you finish.

## Conventions

- `Package.swift` is generated. Change `Package.swift.template`.
- Comments explain why, not what. If a line needed a debugging cycle to get
  right, say what goes wrong without it.
- Shell scripts: `set -e`, `cd` to the repo root, refuse to run if `.root` is
  missing.
- A change to the build is not done until something links against it. A
  configure that succeeds proves very little here.
