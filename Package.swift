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
        url: "https://github.com/Lakr233/libarchive.xcframework/releases/download/upstream.03036ffa409a.1/libarchive.xcframework.zip",
        checksum: "9b2fce99617c7b4cd6f1fdb344a56668296edec6102ce18ebac69ff737bf3bb1"
    )

let package = Package(
    name: "ArchiveKit",
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
        .library(name: "ArchiveKit", targets: ["ArchiveKit"]),
        .library(name: "ArchiveKitDynamic", type: .dynamic, targets: ["ArchiveKit"]),
    ],
    targets: [
        libarchiveTarget,
        .target(
            name: "ArchiveKit",
            dependencies: ["libarchive"],
            linkerSettings: [
                // liblzma, libzstd and liblz4 are already inside the static
                // archive. These four ship with headers in every Apple SDK, so
                // they are linked from the system instead of vendored.
                .linkedLibrary("z"),
                .linkedLibrary("bz2"),
                .linkedLibrary("iconv"),
                .linkedLibrary("xml2"),
            ]
        ),
        .testTarget(
            name: "ArchiveKitTests",
            dependencies: ["ArchiveKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
