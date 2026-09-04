// swift-tools-version: 5.9

import Foundation
import PackageDescription

// Script/build.sh leaves the xcframework it just built in BinaryTarget/, which
// is gitignored. Prefer it when it is there, so a local build can be tested
// before it has been released anywhere.
let localXCFramework = "BinaryTarget/libarchive.xcframework"
let localXCFrameworkExists = FileManager.default.fileExists(
    atPath: URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent(localXCFramework)
        .path
)

let libarchiveTarget: Target = localXCFrameworkExists
    ? .binaryTarget(name: "libarchive", path: localXCFramework)
    : .binaryTarget(
        name: "libarchive",
        url: "https://github.com/https://github.com/Lakr233/libarchive.xcframework.git/releases/download/upstream.27cbc7827172.1/libarchive.xcframework.zip",
        checksum: "f89a85a430ecf5c57fd07e495fdfc12a85a52de52731d10cd43351ba3ff05859"
    )

let package = Package(
    name: "LibArchive",
    platforms: [
        .macOS(.v10_13),
        .macCatalyst(.v13),
        .iOS(.v12),
        .tvOS(.v12),
        .watchOS(.v5),
        .visionOS(.v1),
    ],
    products: [
        // The binary is static either way. This picks how the wrapper around
        // it is linked into your app: straight in, or as one dylib shared by
        // several targets or extensions.
        .library(name: "LibArchive", targets: ["LibArchive"]),
        .library(name: "LibArchiveDynamic", type: .dynamic, targets: ["LibArchive"]),
    ],
    targets: [
        libarchiveTarget,
        .target(
            name: "LibArchive",
            dependencies: ["libarchive"],
            linkerSettings: [
                // liblzma and libzstd are already inside the static archive.
                // These three ship with headers in every Apple SDK, so they are
                // linked from the system instead of vendored.
                .linkedLibrary("z"),
                .linkedLibrary("bz2"),
                .linkedLibrary("iconv"),
            ]
        ),
        .testTarget(
            name: "LibArchiveTests",
            dependencies: ["LibArchive"]
        ),
    ]
)
