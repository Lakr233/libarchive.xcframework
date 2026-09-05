import Foundation

/// Files the app owns so a fresh simulator can unpack, inspect, preview,
/// and pack without picking anything from outside the sandbox.
enum SampleWorkspace {
    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var unpacks: URL {
        documents.appendingPathComponent("Unpacked", isDirectory: true)
    }

    static var packs: URL {
        documents.appendingPathComponent("Archives", isDirectory: true)
    }

    static var sources: URL {
        documents.appendingPathComponent("Sources", isDirectory: true)
    }

    /// A small `.tar.xz` the Unpack tab can open on a device with no files.
    static func makeArchive() throws -> URL {
        let tree = try makeSourceTree()
        let url = packs.appendingPathComponent("Sample.tar.xz")
        try FileManager.default.createDirectory(at: packs, withIntermediateDirectories: true)
        try ArchiveOperations.create(
            sources: [tree],
            to: url,
            recipe: .tarXZ
        )
        AppLog.info(.archive, "wrote sample archive \(url.lastPathComponent)")
        return url
    }

    /// A folder of a few files the Pack tab can compress.
    @discardableResult
    static func makeSourceTree() throws -> URL {
        let root = sources.appendingPathComponent("Sample", isDirectory: true)
        let manager = FileManager.default
        if manager.fileExists(atPath: root.path) {
            try manager.removeItem(at: root)
        }
        try manager.createDirectory(at: root.appendingPathComponent("src"), withIntermediateDirectories: true)
        try manager.createDirectory(at: root.appendingPathComponent("docs"), withIntermediateDirectories: true)
        try """
        # Sample
        Built by Archive with libarchive.
        """.write(to: root.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try """
        #include <stdio.h>
        int main(void) { puts("hello"); return 0; }
        """.write(to: root.appendingPathComponent("src/main.c"), atomically: true, encoding: .utf8)
        try "int twice(int value) { return value * 2; }\n"
            .write(to: root.appendingPathComponent("src/util.c"), atomically: true, encoding: .utf8)
        try String(repeating: "Compressible filler text. ", count: 64)
            .write(to: root.appendingPathComponent("docs/guide.txt"), atomically: true, encoding: .utf8)
        return root
    }
}
