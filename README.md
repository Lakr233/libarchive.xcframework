# libarchive.xcframework

[libarchive](https://github.com/libarchive/libarchive) as a Swift package, built
as one static xcframework covering every Apple platform and architecture. A
GitHub Action re-pins upstream and rebuilds daily.

## Usage

```swift
.package(url: "https://github.com/Lakr233/libarchive.xcframework.git", from: "0.1.0")
```

Then pick one of the two products:

| Product             | What you get                                                              |
| ------------------- | ------------------------------------------------------------------------- |
| `LibArchive`        | Linked straight into your target. The default; nothing to embed or sign.  |
| `LibArchiveDynamic` | The same code as one dylib, for sharing between an app and its extensions. |

The archive itself is static either way — the product only decides how the thin
Swift wrapper around it is linked.

```swift
import LibArchive

let archive = archive_read_new()
archive_read_support_filter_all(archive)
archive_read_support_format_all(archive)
archive_read_open_filename(archive, path, 64 * 1024)

var entry: OpaquePointer?
while archive_read_next_header(archive, &entry) == ARCHIVE_OK {
    print(String(cString: archive_entry_pathname(entry)))
    archive_read_data_skip(archive)
}
archive_read_free(archive)
```

`Example/ArchiveViewerApp.xcodeproj` is a sandboxed iOS 17+ SwiftUI app that
lists, previews, extracts, and creates archives with this package. It writes
its own sample `.tar.xz` on demand, so it runs end to end on a fresh simulator
with no files to feed it.

## Platforms

| Platform          | Architectures         | Minimum deployment target |
| ----------------- | --------------------- | ------------------------- |
| macOS             | x86_64 arm64          | 10.13 (arm64 slice: 11.0) |
| Mac Catalyst      | x86_64 arm64          | 13.1                      |
| iOS               | arm64 arm64e          | 12.0 (arm64e slice: 14.0) |
| iOS Simulator     | x86_64 arm64          | 12.0                      |
| tvOS              | arm64                 | 12.0                      |
| tvOS Simulator    | x86_64 arm64          | 12.0                      |
| watchOS           | arm64_32 arm64        | 5.0                       |
| watchOS Simulator | x86_64 arm64          | 5.0                       |
| visionOS          | arm64                 | 1.0                       |
| visionOS Simulator| arm64                 | 1.0                       |

The floors written into each `Info.plist` are read back out of the built binary,
so they reflect what the toolchain actually produced rather than what the build
asked for.

## What is compiled in

Every optional backend libarchive supports under a permissive licence is turned
on.

| Backend                     | Where it comes from                                    |
| --------------------------- | ------------------------------------------------------ |
| zlib, bzip2, iconv, libxml2 | The Apple SDKs, which ship headers for all four         |
| liblzma (xz)                | Compiled from source, merged into the static archive    |
| libzstd                     | Compiled from source, merged into the static archive    |
| liblz4                      | Compiled from source, merged into the static archive    |
| MD5/SHA digests             | CommonCrypto                                            |
| BLAKE2                      | libarchive's own implementation                         |

## Formats

### Containers

| Format | Read | Write | Notes |
| ------ | :--: | :---: | ----- |
| tar | ✅ | ✅ | v7, ustar, POSIX pax, restricted pax, GNU tar |
| cpio | ✅ | ✅ | binary, odc, newc, PWB, SVR4 with and without CRC |
| zip | ✅ | ✅ | streamable and seekable |
| 7-Zip | ✅ | ✅ | |
| xar | ✅ | ✅ | via the SDK's libxml2 |
| ISO 9660 | ✅ | ✅ | Rock Ridge, Joliet, zisofs |
| mtree | ✅ | ✅ | classic and modern |
| ar | ✅ | ✅ | BSD and SVR4/GNU variants |
| WARC | ✅ | ✅ | |
| RAR | ✅ | — | RAR4 |
| RAR5 | ✅ | — | |
| CAB | ✅ | — | Microsoft cabinet |
| LHA / LZH | ✅ | — | |
| shar | — | ✅ | plain and dump |
| raw | ✅ | ✅ | a single unnamed entry |
| empty | ✅ | — | |

### Compression filters

| Filter | Read | Write | Extensions |
| ------ | :--: | :---: | ---------- |
| none | ✅ | ✅ | |
| gzip | ✅ | ✅ | `.gz`, `.tgz` |
| bzip2 | ✅ | ✅ | `.bz2`, `.tbz` |
| xz | ✅ | ✅ | `.xz`, `.txz` |
| lzma | ✅ | ✅ | `.lzma` |
| lzip | ✅ | ✅ | `.lz` |
| zstd | ✅ | ✅ | `.zst`, `.tzst` |
| lz4 | ✅ | ✅ | `.lz4` |
| compress | ✅ | ✅ | `.Z` |
| uuencode | ✅ | ✅ | `.uu` |
| base64 | — | ✅ | |
| RPM | ✅ | — | reads the payload out of an `.rpm` |
| lzop, lrzip, grzip | ❌ | ❌ | need a helper binary — see below |

### Codecs inside zip and 7-Zip

| | zip | 7-Zip |
| --- | --- | --- |
| Read | store, deflate, bzip2, LZMA, XZ, Zstandard, PPMd | copy, LZMA, LZMA2, bzip2, deflate, PPMd, Zstandard, delta, BCJ x86, ARM64 |
| Write | store, deflate, bzip2, LZMA, XZ, Zstandard | copy, LZMA, LZMA2, bzip2, deflate, PPMd, Zstandard |

Encryption: WinZip AES and legacy ZipCrypto for zip, AES-256/SHA-256 for 7-Zip,
all through CommonCrypto.

### What does not work

`lzop`, `lrzip` and `grzip` stay registered but fail at open with
`ARCHIVE_FATAL`. libarchive implements the last two only by shelling out to a
helper binary, and lzop needs liblzo2, which is GPLv2 and therefore not
vendored here. On iOS, tvOS, watchOS and visionOS these could never have worked
anyway — nothing sandboxed may spawn a helper.

The three vendored libraries are compiled with hidden visibility, so no
`lzma_*`, `ZSTD_*` or `LZ4_*` symbols are exported and an app linking its own
copy of any of them gets no duplicate-symbol conflict.

Left out: **liblzo2**, on licence grounds — it is GPLv2, and everything vendored
here is BSD or 0BSD. OpenSSL, mbedTLS and Nettle are redundant with
CommonCrypto, libb2 is redundant with libarchive's own BLAKE2, and PCRE only
feeds `bsdtar`/`bsdcpio`, which this package does not build.

The external-program filters — `archive_read_support_filter_program` and
friends — are off on every platform. They shell out to a helper binary, which no
sandboxed app can do, and `fork`/`posix_spawn` are unavailable outright on tvOS
and watchOS. Everything the library supports, it decodes in-process.

Those entry points still exist and still link; they report "unable to run
program" and return `ARCHIVE_FATAL`. So do the three formats that reach for a
helper — lzop, lrzip and grzip — rather than disappearing from
`archive_read_support_filter_all`.

liblzma and libzstd are compiled with hidden visibility, so their symbols stay
local to the archive. An app that links its own copy of either gets no
duplicate-symbol conflict.

## Building locally

```bash
./Script/build.sh
```

Fetches the pinned upstreams into `build/src`, builds every variant, assembles
`build/libarchive.xcframework.zip`, and rewrites `Package.swift` with the new
checksum. It also leaves the unzipped framework in `BinaryTarget/`, which
`Package.swift` prefers over the released URL — so `swift test` and the example
app pick up a local build without any manifest editing.

To go back to the released binary, delete `BinaryTarget/` **and** clear the
manifest cache — SwiftPM keys that cache on the manifest's contents, not on the
filesystem the manifest looked at, so the local path stays baked in otherwise:

```bash
rm -rf BinaryTarget .build && swift package purge-cache
```

One platform group at a time:

```bash
./Script/build-platform.sh ios ./build/dest      # macos ios tvos watchos visionos
./Script/merge-xcframework.sh ./build/dest ./build/libarchive.xcframework.zip
```

Re-pin upstream to the newest releases:

```bash
./Script/resolve-upstream.sh latest --write
```

Check that the package builds everywhere:

```bash
./Script/test.sh
```

## Releases

Every published binary comes from the **Build libarchive** workflow, never from
a local build. Two tags come out of each run:

| Tag                        | Holds                                                    |
| -------------------------- | -------------------------------------------------------- |
| `upstream.<ref>.<rev>`     | `libarchive.xcframework.zip`, keyed to the libarchive commit |
| `<major>.<minor>.<patch>`  | The package release you depend on                        |

`<ref>` is the first 12 characters of the pinned libarchive commit and `<rev>`
counts rebuilds of that same commit, so touching `Vendor/` or the build scripts
publishes a fresh binary without inventing a new upstream version. `Package.swift`
is rewritten by the workflow to point at the storage tag it just published.

The daily schedule re-pins to the newest upstream releases and builds only when
that commit has never been published. Run the workflow by hand to force a
rebuild or to name a specific package version.

## Credits

- [libarchive](https://github.com/libarchive/libarchive) — BSD-2-Clause
- [xz](https://github.com/tukaani-project/xz) — 0BSD
- [zstd](https://github.com/facebook/zstd) — BSD-3-Clause (only the library is built)
- [lz4](https://github.com/lz4/lz4) — BSD-2-Clause (only the library is built)

The packaging here is MIT. All four upstream notices are reproduced in full in
[`LICENSE`](LICENSE), which is what BSD-2 and BSD-3 ask of a binary
redistribution — and a released xcframework is exactly that.
- Packaging follows [Lakr233/openssl-spm](https://github.com/Lakr233/openssl-spm)
