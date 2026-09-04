import Foundation
import LibArchive

/// File-URL in, result out. No SwiftUI types, so XCTest can call every
/// operation the app ships. Callers that hold a security-scoped URL keep
/// access around the call; this type does not.
enum ArchiveOperations {
    struct Entry: Hashable, Identifiable, Sendable {
        var id: String { path }
        let path: String
        let size: Int64
        let isDirectory: Bool
        let modified: Date?
    }

    struct Failure: Error, LocalizedError, Equatable {
        var errorDescription: String?
    }

    struct Preview: Equatable, Sendable {
        let path: String
        let data: Data
        let truncated: Bool
        let totalSize: Int64
    }

    enum Container: String, CaseIterable, Identifiable, Sendable {
        case zip
        case pax
        case sevenZip
        case cpio
        case ustar

        var id: String { rawValue }

        var title: String {
            switch self {
            case .zip: "Zip"
            case .pax: "tar"
            case .sevenZip: "7-Zip"
            case .cpio: "cpio"
            case .ustar: "ustar"
            }
        }

        var pathExtension: String {
            switch self {
            case .zip: "zip"
            case .pax, .ustar: "tar"
            case .sevenZip: "7z"
            case .cpio: "cpio"
            }
        }

        /// Zip and 7-Zip compress inside the container; an extra filter
        /// would wrap the file again and confuse the destination name.
        var usesExternalFilter: Bool {
            self == .pax || self == .ustar || self == .cpio
        }

        fileprivate var setFormat: (OpaquePointer?) -> Int32 {
            switch self {
            case .zip: archive_write_set_format_zip
            case .pax: archive_write_set_format_pax_restricted
            case .sevenZip: archive_write_set_format_7zip
            case .cpio: archive_write_set_format_cpio_newc
            case .ustar: archive_write_set_format_ustar
            }
        }
    }

    enum Filter: String, CaseIterable, Identifiable, Sendable {
        case none
        case gzip
        case bzip2
        case xz
        case zstd
        case lz4

        var id: String { rawValue }

        var title: String {
            switch self {
            case .none: "None"
            case .gzip: "gzip"
            case .bzip2: "bzip2"
            case .xz: "xz"
            case .zstd: "zstd"
            case .lz4: "lz4"
            }
        }

        var pathExtension: String? {
            switch self {
            case .none: nil
            case .gzip: "gz"
            case .bzip2: "bz2"
            case .xz: "xz"
            case .zstd: "zst"
            case .lz4: "lz4"
            }
        }

        fileprivate var addFilter: (OpaquePointer?) -> Int32 {
            switch self {
            case .none: archive_write_add_filter_none
            case .gzip: archive_write_add_filter_gzip
            case .bzip2: archive_write_add_filter_bzip2
            case .xz: archive_write_add_filter_xz
            case .zstd: archive_write_add_filter_zstd
            case .lz4: archive_write_add_filter_lz4
            }
        }
    }

    struct Recipe: Equatable, Hashable, Sendable {
        var container: Container
        var filter: Filter
        /// 0...9. Applied to gzip, xz, zstd, zip, and 7-Zip when they accept it.
        var compressionLevel: Int
        var skipHidden: Bool

        static let zip = Recipe(container: .zip, filter: .none, compressionLevel: 6, skipHidden: true)
        static let tarXZ = Recipe(container: .pax, filter: .xz, compressionLevel: 6, skipHidden: true)

        var pathExtension: String {
            if container.usesExternalFilter, let extra = filter.pathExtension {
                return "\(container.pathExtension).\(extra)"
            }
            return container.pathExtension
        }
    }

    private static let blockSize = 64 * 1024
    private static let fileTypeDirectory: UInt32 = 0o040_000
    private static let fileTypeRegular: UInt32 = 0o100_000
    /// `SECURE_NOABSOLUTEPATHS` is omitted on purpose: we rewrite each
    /// entry to an absolute path under `directory` after rejecting `..`
    /// and rooted names ourselves. Leaving the flag on would refuse the
    /// rewritten path and write nothing.
    private static let extractFlags =
        ARCHIVE_EXTRACT_TIME
            | ARCHIVE_EXTRACT_PERM
            | ARCHIVE_EXTRACT_SECURE_SYMLINKS
            | ARCHIVE_EXTRACT_SECURE_NODOTDOT
            | ARCHIVE_EXTRACT_SAFE_WRITES

    // MARK: - List

    static func list(
        at url: URL,
        progress: ((Double) -> Void)? = nil
    ) throws -> [Entry] {
        let totalBytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let archive = try openReader(url)
        defer { archive_read_free(archive) }

        var entries: [Entry] = []
        var entry: OpaquePointer?
        while true {
            let status = archive_read_next_header(archive, &entry)
            if status == ARCHIVE_EOF { break }
            guard status == ARCHIVE_OK || status == ARCHIVE_WARN else {
                throw failure(archive)
            }
            let listed = makeEntry(entry)
            if listed.path != "." && listed.path != ".." {
                entries.append(listed)
            }
            archive_read_data_skip(archive)
            reportReadProgress(archive, totalBytes: totalBytes, progress)
        }
        progress?(1)
        return entries
    }

    // MARK: - Extract all

    static func extract(
        archive url: URL,
        to directory: URL,
        progress: ((Double, String) -> Void)? = nil
    ) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let totalBytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let archive = try openReader(url)
        defer { archive_read_free(archive) }
        let disk = try openDisk()
        defer { archive_write_free(disk) }

        var entry: OpaquePointer?
        while true {
            let status = archive_read_next_header(archive, &entry)
            if status == ARCHIVE_EOF { break }
            guard status == ARCHIVE_OK || status == ARCHIVE_WARN else {
                throw failure(archive)
            }
            let relative = makeEntry(entry).path
            guard let destination = safeDestination(directory: directory, relative: relative) else {
                throw Failure(errorDescription: "The archive contains an unsafe path.")
            }
            destination.path.withCString { archive_entry_set_pathname_utf8(entry, $0) }
            let extracted = archive_read_extract2(archive, entry, disk)
            guard extracted == ARCHIVE_OK || extracted == ARCHIVE_WARN else {
                throw failure(archive)
            }
            let consumed = totalBytes > 0
                ? min(1, Double(archive_filter_bytes(archive, -1)) / Double(totalBytes))
                : 0
            progress?(consumed, relative)
        }
        progress?(1, "")
    }

    // MARK: - Extract one

    static func extract(
        archive url: URL,
        entry path: String,
        to file: URL,
        progress: ((Double) -> Void)? = nil
    ) throws {
        let archive = try openReader(url)
        defer { archive_read_free(archive) }

        var entry: OpaquePointer?
        while true {
            let status = archive_read_next_header(archive, &entry)
            if status == ARCHIVE_EOF {
                throw Failure(errorDescription: "That item is not in this archive.")
            }
            guard status == ARCHIVE_OK || status == ARCHIVE_WARN else {
                throw failure(archive)
            }
            guard makeEntry(entry).path == path else {
                archive_read_data_skip(archive)
                continue
            }
            if archive_entry_filetype(entry) == fileTypeDirectory {
                try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
                progress?(1)
                return
            }
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.removeItem(at: file)
            }
            let size = max(0, archive_entry_size(entry))
            FileManager.default.createFile(atPath: file.path, contents: Data())
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try copyData(from: archive, to: handle, size: size, progress: progress)
            progress?(1)
            return
        }
    }

    // MARK: - Preview

    static func preview(
        archive url: URL,
        entry path: String,
        limit: Int = 256 * 1024
    ) throws -> Preview {
        let archive = try openReader(url)
        defer { archive_read_free(archive) }

        var entry: OpaquePointer?
        while true {
            let status = archive_read_next_header(archive, &entry)
            if status == ARCHIVE_EOF {
                throw Failure(errorDescription: "That item is not in this archive.")
            }
            guard status == ARCHIVE_OK || status == ARCHIVE_WARN else {
                throw failure(archive)
            }
            let listed = makeEntry(entry)
            guard listed.path == path else {
                archive_read_data_skip(archive)
                continue
            }
            if listed.isDirectory {
                return Preview(path: path, data: Data(), truncated: false, totalSize: 0)
            }
            var collected = Data()
            var buffer = [UInt8](repeating: 0, count: min(blockSize, max(limit, 1)))
            while collected.count < limit {
                let want = min(buffer.count, limit - collected.count)
                let got = archive_read_data(archive, &buffer, want)
                if got == 0 { break }
                guard got > 0 else { throw failure(archive) }
                collected.append(contentsOf: buffer.prefix(Int(got)))
            }
            return Preview(
                path: path,
                data: collected,
                truncated: collected.count >= limit || listed.size > Int64(collected.count),
                totalSize: listed.size
            )
        }
    }

    // MARK: - Create

    static func create(
        sources: [URL],
        to destination: URL,
        recipe: Recipe,
        progress: ((Double, String) -> Void)? = nil
    ) throws {
        let members = try flatten(sources, skipHidden: recipe.skipHidden)
        let totalBytes = members.reduce(Int64(0)) { $0 + $1.size }
        var written: Int64 = 0

        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        guard let archive = archive_write_new() else {
            throw Failure(errorDescription: "Not enough memory to create the archive.")
        }
        defer { archive_write_free(archive) }

        let filter = recipe.container.usesExternalFilter ? recipe.filter : .none
        guard filter.addFilter(archive) == ARCHIVE_OK else { throw failure(archive) }
        guard recipe.container.setFormat(archive) == ARCHIVE_OK else { throw failure(archive) }
        applyCompressionLevel(archive, recipe: recipe, filter: filter)

        let opened = destination.withUnsafeFileSystemRepresentation { path in
            archive_write_open_filename(archive, path)
        }
        guard opened == ARCHIVE_OK else { throw failure(archive) }

        for member in members {
            try writeMember(archive, member: member)
            if !member.isDirectory {
                written += member.size
            }
            let fraction = totalBytes > 0 ? min(1, Double(written) / Double(totalBytes)) : 1
            progress?(fraction, member.path)
        }

        guard archive_write_close(archive) == ARCHIVE_OK else { throw failure(archive) }
        progress?(1, "")
    }

    // MARK: - Internals

    private struct Member {
        let url: URL
        let path: String
        let size: Int64
        let isDirectory: Bool
        let modified: Date
    }

    private static func openReader(_ url: URL) throws -> OpaquePointer {
        guard let archive = archive_read_new() else {
            throw Failure(errorDescription: "Not enough memory to read the archive.")
        }
        archive_read_support_filter_all(archive)
        archive_read_support_format_all(archive)
        let opened = url.withUnsafeFileSystemRepresentation { path in
            archive_read_open_filename(archive, path, Int(blockSize))
        }
        guard opened == ARCHIVE_OK else {
            let error = failure(archive)
            archive_read_free(archive)
            throw error
        }
        return archive
    }

    private static func safeDestination(directory: URL, relative: String) -> URL? {
        guard !relative.hasPrefix("/") else { return nil }
        let parts = relative.split(separator: "/", omittingEmptySubsequences: true)
        guard !parts.isEmpty, !parts.contains("..") else { return nil }
        return directory.appendingPathComponent(parts.joined(separator: "/"))
    }

    private static func openDisk() throws -> OpaquePointer {
        guard let disk = archive_write_disk_new() else {
            throw Failure(errorDescription: "Not enough memory to extract.")
        }
        archive_write_disk_set_options(disk, extractFlags)
        archive_write_disk_set_standard_lookup(disk)
        return disk
    }

    private static func makeEntry(_ entry: OpaquePointer?) -> Entry {
        let path: UnsafePointer<CChar>? = archive_entry_pathname_utf8(entry)
            ?? archive_entry_pathname(entry)
        let modified = archive_entry_mtime_is_set(entry) != 0
            ? Date(timeIntervalSince1970: TimeInterval(archive_entry_mtime(entry)))
            : nil
        return Entry(
            path: path.map { String(cString: $0) } ?? "(unnamed)",
            size: archive_entry_size(entry),
            isDirectory: archive_entry_filetype(entry) == fileTypeDirectory,
            modified: modified
        )
    }

    private static func reportReadProgress(
        _ archive: OpaquePointer?,
        totalBytes: Int,
        _ progress: ((Double) -> Void)?
    ) {
        guard let progress, totalBytes > 0 else { return }
        let consumed = archive_filter_bytes(archive, -1)
        progress(min(1, Double(consumed) / Double(totalBytes)))
    }

    private static func copyData(
        from archive: OpaquePointer?,
        to handle: FileHandle,
        size: Int64,
        progress: ((Double) -> Void)?
    ) throws {
        var copied: Int64 = 0
        var buffer = [UInt8](repeating: 0, count: blockSize)
        while true {
            let got = archive_read_data(archive, &buffer, buffer.count)
            if got == 0 { break }
            guard got > 0 else { throw failure(archive) }
            try handle.write(contentsOf: buffer.prefix(Int(got)))
            copied += Int64(got)
            if size > 0 {
                progress?(min(1, Double(copied) / Double(size)))
            }
        }
    }

    private static func flatten(_ sources: [URL], skipHidden: Bool) throws -> [Member] {
        var members: [Member] = []
        let manager = FileManager.default
        for source in sources {
            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: source.path, isDirectory: &isDirectory) else {
                throw Failure(errorDescription: "“\(source.lastPathComponent)” could not be found.")
            }
            let rootName = source.lastPathComponent
            if skipHidden, rootName.hasPrefix(".") { continue }
            if isDirectory.boolValue {
                members.append(try member(at: source, path: rootName, isDirectory: true))
                let enumerator = manager.enumerator(
                    at: source,
                    includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
                    options: skipHidden ? [.skipsHiddenFiles] : []
                )
                while let url = enumerator?.nextObject() as? URL {
                    let values = try url.resourceValues(forKeys: [.isDirectoryKey])
                    let directory = values.isDirectory == true
                    let path = relativePath(of: url, under: source, rootName: rootName)
                    members.append(try member(at: url, path: path, isDirectory: directory))
                }
            } else {
                members.append(try member(at: source, path: rootName, isDirectory: false))
            }
        }
        return members
    }

    private static func relativePath(of url: URL, under source: URL, rootName: String) -> String {
        let sourcePath = source.standardizedFileURL.path
        let urlPath = url.standardizedFileURL.path
        let prefix = sourcePath.hasSuffix("/") ? sourcePath : sourcePath + "/"
        if urlPath.hasPrefix(prefix) {
            return rootName + "/" + String(urlPath.dropFirst(prefix.count))
        }
        return rootName + "/" + url.lastPathComponent
    }

    private static func member(at url: URL, path: String, isDirectory: Bool) throws -> Member {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return Member(
            url: url,
            path: path,
            size: isDirectory ? 0 : Int64(values.fileSize ?? 0),
            isDirectory: isDirectory,
            modified: values.contentModificationDate ?? Date()
        )
    }

    private static func writeMember(_ archive: OpaquePointer?, member: Member) throws {
        guard let entry = archive_entry_new() else {
            throw Failure(errorDescription: "Not enough memory to create the archive.")
        }
        defer { archive_entry_free(entry) }

        member.path.withCString { archive_entry_set_pathname_utf8(entry, $0) }
        archive_entry_set_mtime(entry, time_t(member.modified.timeIntervalSince1970), 0)
        if member.isDirectory {
            archive_entry_set_filetype(entry, fileTypeDirectory)
            archive_entry_set_perm(entry, 0o755)
        } else {
            archive_entry_set_filetype(entry, fileTypeRegular)
            archive_entry_set_perm(entry, 0o644)
            archive_entry_set_size(entry, member.size)
        }
        guard archive_write_header(archive, entry) == ARCHIVE_OK else { throw failure(archive) }
        guard !member.isDirectory else { return }

        let handle = try FileHandle(forReadingFrom: member.url)
        defer { try? handle.close() }
        while let chunk = try handle.read(upToCount: blockSize), !chunk.isEmpty {
            let wrote = chunk.withUnsafeBytes { raw in
                archive_write_data(archive, raw.baseAddress, chunk.count)
            }
            guard wrote == chunk.count else { throw failure(archive) }
        }
    }

    private static func applyCompressionLevel(
        _ archive: OpaquePointer?,
        recipe: Recipe,
        filter: Filter
    ) {
        let level = String(min(9, max(0, recipe.compressionLevel)))
        _ = level.withCString { value in
            switch (recipe.container, filter) {
            case (.zip, _):
                archive_write_set_format_option(archive, "zip", "compression-level", value)
            case (.sevenZip, _):
                archive_write_set_format_option(archive, "7zip", "compression-level", value)
            case (_, .gzip):
                archive_write_set_filter_option(archive, "gzip", "compression-level", value)
            case (_, .xz):
                archive_write_set_filter_option(archive, "xz", "compression-level", value)
            case (_, .zstd):
                archive_write_set_filter_option(archive, "zstd", "compression-level", value)
            default:
                ARCHIVE_OK
            }
        }
    }

    private static func failure(_ archive: OpaquePointer?) -> Failure {
        let message = archive_error_string(archive).map { String(cString: $0) }
        return Failure(errorDescription: message ?? "This file is not an archive.")
    }
}
