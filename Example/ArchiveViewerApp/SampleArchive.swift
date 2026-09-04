import Foundation
import LibArchive

/// Writes a small `.tar.xz` into the app's own temporary directory.
///
/// A file picker needs a file to pick, and a freshly installed app in a
/// simulator has none. Building one here keeps the demo runnable with nothing
/// outside the sandbox, and exercises libarchive's write path on the way in.
enum SampleArchive {
    /// A nil `contents` is a directory entry. Order matters: tar readers expect
    /// a directory before the files inside it.
    private static let entries: [(path: String, contents: String?)] = [
        ("README.md", "# Sample\n\nBuilt by ArchiveViewerApp with libarchive.\n"),
        ("src", nil),
        ("src/main.c", "#include <stdio.h>\n\nint main(void) {\n    puts(\"hello\");\n    return 0;\n}\n"),
        ("src/util.c", "int twice(int value) { return value * 2; }\n"),
        ("docs", nil),
        ("docs/guide.txt", String(repeating: "Compressible filler text. ", count: 64)),
    ]

    static func make() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Sample.tar.xz")

        guard let archive = archive_write_new() else {
            throw ArchiveReader.Failure(errorDescription: "Out of memory")
        }
        defer { archive_write_free(archive) }

        archive_write_add_filter_xz(archive)
        archive_write_set_format_pax_restricted(archive)

        let opened = url.withUnsafeFileSystemRepresentation { path in
            archive_write_open_filename(archive, path)
        }
        guard opened == ARCHIVE_OK else {
            throw failure(archive)
        }

        for entry in entries {
            try write(archive: archive, path: entry.path, contents: entry.contents)
        }

        guard archive_write_close(archive) == ARCHIVE_OK else {
            throw failure(archive)
        }
        return url
    }

    private static func write(archive: OpaquePointer, path: String, contents: String?) throws {
        guard let entry = archive_entry_new() else {
            throw ArchiveReader.Failure(errorDescription: "Out of memory")
        }
        defer { archive_entry_free(entry) }

        let bytes = Array((contents ?? "").utf8)
        archive_entry_set_pathname(entry, path)
        archive_entry_set_mtime(entry, Int(Date().timeIntervalSince1970), 0)

        if contents == nil {
            archive_entry_set_filetype(entry, 0o040_000) // AE_IFDIR
            archive_entry_set_perm(entry, 0o755)
        } else {
            archive_entry_set_filetype(entry, 0o100_000) // AE_IFREG
            archive_entry_set_perm(entry, 0o644)
            archive_entry_set_size(entry, Int64(bytes.count))
        }

        guard archive_write_header(archive, entry) == ARCHIVE_OK else {
            throw failure(archive)
        }
        guard bytes.isEmpty || archive_write_data(archive, bytes, bytes.count) == bytes.count else {
            throw failure(archive)
        }
    }

    private static func failure(_ archive: OpaquePointer?) -> ArchiveReader.Failure {
        let message = archive_error_string(archive).map { String(cString: $0) }
        return ArchiveReader.Failure(errorDescription: message ?? "The sample archive couldn't be written.")
    }
}
