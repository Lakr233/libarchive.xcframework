import LibArchive
import XCTest
@testable import ArchiveViewerApp

/// Drives the shipped archive functions on a generated archive. Expected
/// bytes come from the files this test wrote, not from a hardcoded blob.
final class ArchiveOperationsTests: XCTestCase {
    private var folder: URL!
    private let files: [(name: String, body: String)] = [
        ("alpha.txt", "alpha contents\n"),
        ("nested/beta.txt", "beta contents\n"),
    ]

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArchiveOps-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for file in files {
            let url = folder.appendingPathComponent(file.name)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try file.body.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testPlainZipRoundTripListExtractPreview() throws {
        let archive = folder.appendingPathComponent("plain.zip")
        try ArchiveOperations.create(
            sources: [folder.appendingPathComponent("alpha.txt"), folder.appendingPathComponent("nested")],
            to: archive,
            recipe: .zip
        )

        let listed = try ArchiveOperations.list(at: archive)
        let paths = Set(listed.map(\.path))
        XCTAssertTrue(paths.contains("alpha.txt"))
        XCTAssertTrue(paths.contains("nested/beta.txt") || paths.contains("nested") && paths.contains("nested/beta.txt"))

        let unpacked = folder.appendingPathComponent("out", isDirectory: true)
        try ArchiveOperations.extract(archive: archive, to: unpacked)
        XCTAssertEqual(
            try String(contentsOf: unpacked.appendingPathComponent("alpha.txt"), encoding: .utf8),
            "alpha contents\n"
        )
        XCTAssertEqual(
            try String(contentsOf: unpacked.appendingPathComponent("nested/beta.txt"), encoding: .utf8),
            "beta contents\n"
        )

        let oneRoot = folder.appendingPathComponent("only", isDirectory: true)
        let one = try ArchiveOperations.extract(archive: archive, entry: "alpha.txt", into: oneRoot)
        XCTAssertEqual(one, ArchiveOperations.safeDestination(directory: oneRoot, relative: "alpha.txt"))
        XCTAssertEqual(try String(contentsOf: one, encoding: .utf8), "alpha contents\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: oneRoot.appendingPathComponent("nested").path))

        let preview = try ArchiveOperations.preview(archive: archive, entry: "alpha.txt")
        XCTAssertEqual(String(data: preview.data, encoding: .utf8), "alpha contents\n")
        XCTAssertEqual(preview.path, "alpha.txt")
        XCTAssertFalse(preview.truncated)
    }

    func testAdvancedTarXZIsReadableBack() throws {
        let archive = folder.appendingPathComponent("advanced.tar.xz")
        let recipe = ArchiveOperations.Recipe(
            container: .pax,
            filter: .xz,
            compressionLevel: 6,
            skipHidden: true
        )
        try ArchiveOperations.create(
            sources: [folder.appendingPathComponent("alpha.txt")],
            to: archive,
            recipe: recipe
        )
        let listed = try ArchiveOperations.list(at: archive)
        XCTAssertEqual(listed.map(\.path), ["alpha.txt"])
        let preview = try ArchiveOperations.preview(archive: archive, entry: "alpha.txt")
        XCTAssertEqual(String(data: preview.data, encoding: .utf8), "alpha contents\n")

        let unpacked = folder.appendingPathComponent("adv-out", isDirectory: true)
        try ArchiveOperations.extract(archive: archive, to: unpacked)
        XCTAssertEqual(
            try String(contentsOf: unpacked.appendingPathComponent("alpha.txt"), encoding: .utf8),
            "alpha contents\n"
        )
    }

    func testExtractOneReplacesExistingFile() throws {
        let archive = folder.appendingPathComponent("plain.zip")
        try ArchiveOperations.create(
            sources: [folder.appendingPathComponent("alpha.txt")],
            to: archive,
            recipe: .zip
        )
        let root = folder.appendingPathComponent("one", isDirectory: true)
        let dest = try XCTUnwrap(ArchiveOperations.safeDestination(directory: root, relative: "alpha.txt"))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "much longer leftover payload that must not remain\n".write(to: dest, atomically: true, encoding: .utf8)
        try ArchiveOperations.extract(archive: archive, entry: "alpha.txt", into: root)
        XCTAssertEqual(try String(contentsOf: dest, encoding: .utf8), "alpha contents\n")
    }

    func testExtractAllRejectsParentPath() throws {
        let archive = folder.appendingPathComponent("slip.zip")
        guard let writer = archive_write_new() else {
            XCTFail("writer")
            return
        }
        defer { archive_write_free(writer) }
        XCTAssertEqual(archive_write_set_format_zip(writer), ARCHIVE_OK)
        XCTAssertEqual(
            archive.withUnsafeFileSystemRepresentation { archive_write_open_filename(writer, $0) },
            ARCHIVE_OK
        )
        let entry = archive_entry_new()
        defer { archive_entry_free(entry) }
        "../escape.txt".withCString { archive_entry_set_pathname_utf8(entry, $0) }
        archive_entry_set_filetype(entry, 0o100_000)
        archive_entry_set_perm(entry, 0o644)
        archive_entry_set_size(entry, 4)
        archive_entry_set_mtime(entry, 1_700_000_000, 0)
        XCTAssertEqual(archive_write_header(writer, entry), ARCHIVE_OK)
        var bytes = Array("nope".utf8)
        XCTAssertEqual(archive_write_data(writer, &bytes, bytes.count), bytes.count)
        XCTAssertEqual(archive_write_close(writer), ARCHIVE_OK)

        let dest = folder.appendingPathComponent("safe", isDirectory: true)
        XCTAssertThrowsError(try ArchiveOperations.extract(archive: archive, to: dest))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.appendingPathComponent("escape.txt").path))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: folder.appendingPathComponent("escape.txt").path
            )
        )
    }

    /// Extract-one must not honor `../` the way `appendingPathComponent` would.
    func testExtractOneParentPathStaysInsideRoot() throws {
        let archive = folder.appendingPathComponent("slip-one.zip")
        guard let writer = archive_write_new() else {
            XCTFail("writer")
            return
        }
        defer { archive_write_free(writer) }
        XCTAssertEqual(archive_write_set_format_zip(writer), ARCHIVE_OK)
        XCTAssertEqual(
            archive.withUnsafeFileSystemRepresentation { archive_write_open_filename(writer, $0) },
            ARCHIVE_OK
        )
        let entry = archive_entry_new()
        defer { archive_entry_free(entry) }
        "../escape.txt".withCString { archive_entry_set_pathname_utf8(entry, $0) }
        archive_entry_set_filetype(entry, 0o100_000)
        archive_entry_set_perm(entry, 0o644)
        archive_entry_set_size(entry, 4)
        archive_entry_set_mtime(entry, 1_700_000_000, 0)
        XCTAssertEqual(archive_write_header(writer, entry), ARCHIVE_OK)
        var bytes = Array("nope".utf8)
        XCTAssertEqual(archive_write_data(writer, &bytes, bytes.count), bytes.count)
        XCTAssertEqual(archive_write_close(writer), ARCHIVE_OK)

        let unpack = folder.appendingPathComponent("Unpacked", isDirectory: true)
        try FileManager.default.createDirectory(at: unpack, withIntermediateDirectories: true)
        XCTAssertNil(ArchiveOperations.safeDestination(directory: unpack, relative: "../escape.txt"))
        XCTAssertThrowsError(
            try ArchiveOperations.extract(archive: archive, entry: "../escape.txt", into: unpack)
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: unpack.appendingPathComponent("escape.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("escape.txt").path))
        let leaked = unpack.appendingPathComponent("../escape.txt").standardizedFileURL
        XCTAssertEqual(leaked.deletingLastPathComponent().standardizedFileURL, folder.standardizedFileURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: leaked.path))
    }
}
