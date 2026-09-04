import Foundation
import LibArchive

/// Lists what is inside an archive without unpacking anything.
enum ArchiveReader {
    struct Entry {
        let path: String
        let size: Int64
        let isDirectory: Bool
        let modified: Date?
    }

    struct Failure: LocalizedError {
        let errorDescription: String?
    }

    /// Walks every header in `url`, reporting how far through the file it is.
    ///
    /// `progress` is called on an arbitrary queue, one entry at a time. The
    /// fraction comes from the number of compressed bytes libarchive has
    /// consumed, so it tracks the file itself rather than the entry count --
    /// which is unknown until the walk is over.
    static func listEntries(
        at url: URL,
        progress: @escaping (Double) -> Void
    ) throws -> [Entry] {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }

        let totalBytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0

        guard let archive = archive_read_new() else {
            throw Failure(errorDescription: "Out of memory")
        }
        defer { archive_read_free(archive) }

        archive_read_support_filter_all(archive)
        archive_read_support_format_all(archive)

        let opened = url.withUnsafeFileSystemRepresentation { path in
            archive_read_open_filename(archive, path, 64 * 1024)
        }
        guard opened == ARCHIVE_OK else {
            throw failure(archive)
        }

        var entries: [Entry] = []
        var entry: OpaquePointer?

        while true {
            let status = archive_read_next_header(archive, &entry)
            if status == ARCHIVE_EOF { break }
            // ARCHIVE_WARN still yields a usable header -- a mangled mtime, an
            // unsupported attribute. Only a hard error ends the walk.
            guard status == ARCHIVE_OK || status == ARCHIVE_WARN else {
                throw failure(archive)
            }

            entries.append(makeEntry(entry))
            archive_read_data_skip(archive)

            if totalBytes > 0 {
                let consumed = archive_filter_bytes(archive, -1)
                progress(min(1, Double(consumed) / Double(totalBytes)))
            }
        }

        progress(1)
        return entries
    }

    private static func makeEntry(_ entry: OpaquePointer?) -> Entry {
        // Non-UTF-8 names come back through the _utf8 accessor as NULL, so fall
        // back to the raw one before giving up on the name entirely.
        let path: UnsafePointer<CChar>? = archive_entry_pathname_utf8(entry)
            ?? archive_entry_pathname(entry)
        let modified = archive_entry_mtime_is_set(entry) != 0
            ? Date(timeIntervalSince1970: TimeInterval(archive_entry_mtime(entry)))
            : nil

        return Entry(
            path: path.map { String(cString: $0) } ?? "(unnamed)",
            size: archive_entry_size(entry),
            isDirectory: archive_entry_filetype(entry) == 0o040_000, // AE_IFDIR
            modified: modified
        )
    }

    private static func failure(_ archive: OpaquePointer?) -> Failure {
        let message = archive_error_string(archive).map { String(cString: $0) }
        return Failure(errorDescription: message ?? "This file doesn't look like an archive.")
    }
}
