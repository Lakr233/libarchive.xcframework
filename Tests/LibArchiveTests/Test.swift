import LibArchive
import XCTest

final class LibArchiveTests: XCTestCase {
    private let entries = [
        ("hello.txt", "hello libarchive\n"),
        ("nested/dir/second.txt", "second file\n"),
    ]

    func testVersion() {
        let version = String(cString: archive_version_string())
        XCTAssertTrue(version.hasPrefix("libarchive "), version)
    }

    /// The two filters compiled from source. `ARCHIVE_OK` here rather than
    /// `ARCHIVE_WARN` is what says liblzma and libzstd actually made it into
    /// the binary instead of being quietly skipped at configure time.
    func testBundledFiltersAreCompiledIn() {
        let archive = archive_read_new()
        defer { archive_read_free(archive) }
        XCTAssertEqual(archive_read_support_filter_xz(archive), ARCHIVE_OK)
        XCTAssertEqual(archive_read_support_filter_zstd(archive), ARCHIVE_OK)
        XCTAssertEqual(archive_read_support_filter_lz4(archive), ARCHIVE_OK)
        XCTAssertEqual(archive_read_support_filter_gzip(archive), ARCHIVE_OK)
        XCTAssertEqual(archive_read_support_filter_bzip2(archive), ARCHIVE_OK)
    }

    /// xar is the one format that needs libxml2, which comes from the SDK
    /// rather than being vendored -- so this is really checking that the
    /// cross-compiled build found the SDK copy and not the host's.
    func testXarIsCompiledIn() throws {
        let archive = try XCTUnwrap(archive_read_new())
        defer { archive_read_free(archive) }
        XCTAssertEqual(archive_read_support_format_xar(archive), ARCHIVE_OK)
    }

    /// The external-program filters are built without fork/posix_spawn, so
    /// their two helpers come from a stub in this repo. If that stub ever goes
    /// missing the library stops linking; if it ever starts succeeding, a
    /// sandboxed app would be trying to spawn a binary it cannot spawn.
    func testExternalProgramFilterFailsCleanly() throws {
        let archive = try XCTUnwrap(archive_read_new())
        defer { archive_read_free(archive) }

        // Registering still succeeds -- the helper is only spawned when the
        // stream is opened.
        XCTAssertEqual(archive_read_support_filter_program(archive, "/usr/bin/cat"), ARCHIVE_OK)
        XCTAssertEqual(archive_read_support_format_all(archive), ARCHIVE_OK)

        let bytes = Array("never reaches a format reader".utf8)
        XCTAssertEqual(archive_read_open_memory(archive, bytes, bytes.count), ARCHIVE_FATAL)
        XCTAssertEqual(
            archive_error_string(archive).map { String(cString: $0) },
            "Can't initialize filter; unable to run program \"/usr/bin/cat\""
        )
    }

    func testRoundTripThroughEveryFilter() throws {
        let filters: [(name: String, add: (OpaquePointer?) -> Int32)] = [
            ("gzip", archive_write_add_filter_gzip),
            ("bzip2", archive_write_add_filter_bzip2),
            ("xz", archive_write_add_filter_xz),
            ("zstd", archive_write_add_filter_zstd),
            ("lz4", archive_write_add_filter_lz4),
        ]

        for filter in filters {
            let archived = try write(filter: filter.add)
            XCTAssertEqual(try read(archived), entries.map { $0.0 }, filter.name)
        }
    }

    // MARK: - Helpers

    private func write(filter: (OpaquePointer?) -> Int32) throws -> Data {
        let archive = try XCTUnwrap(archive_write_new())

        // libarchive keeps both pointers for the whole write, past the call
        // that hands them over, so neither can come from an inout conversion.
        // Their deallocation is declared before archive_write_free so it runs
        // after it: closing the writer flushes into the buffer and updates the
        // count, and a test that fails mid-write still unwinds through that.
        let capacity = 64 * 1024
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: capacity, alignment: 1)
        let used = UnsafeMutablePointer<Int>.allocate(capacity: 1)
        used.initialize(to: 0)
        defer {
            buffer.deallocate()
            used.deallocate()
        }
        defer { archive_write_free(archive) }

        XCTAssertEqual(filter(archive), ARCHIVE_OK)
        XCTAssertEqual(archive_write_set_format_pax_restricted(archive), ARCHIVE_OK)
        XCTAssertEqual(archive_write_open_memory(archive, buffer, capacity, used), ARCHIVE_OK)

        for (path, contents) in entries {
            let entry = try XCTUnwrap(archive_entry_new())
            defer { archive_entry_free(entry) }

            let bytes = Array(contents.utf8)
            archive_entry_set_pathname(entry, path)
            archive_entry_set_size(entry, Int64(bytes.count))
            archive_entry_set_filetype(entry, 0o100_000) // AE_IFREG
            archive_entry_set_perm(entry, 0o644)
            XCTAssertEqual(archive_write_header(archive, entry), ARCHIVE_OK)
            XCTAssertEqual(archive_write_data(archive, bytes, bytes.count), bytes.count)
        }

        XCTAssertEqual(archive_write_close(archive), ARCHIVE_OK)
        return Data(bytes: buffer, count: used.pointee)
    }

    private func read(_ data: Data) throws -> [String] {
        let archive = try XCTUnwrap(archive_read_new())
        defer { archive_read_free(archive) }

        XCTAssertEqual(archive_read_support_filter_all(archive), ARCHIVE_OK)
        XCTAssertEqual(archive_read_support_format_all(archive), ARCHIVE_OK)

        var paths: [String] = []
        try data.withUnsafeBytes { raw in
            XCTAssertEqual(
                archive_read_open_memory(archive, raw.baseAddress, raw.count),
                ARCHIVE_OK
            )

            var entry: OpaquePointer?
            while archive_read_next_header(archive, &entry) == ARCHIVE_OK {
                paths.append(String(cString: archive_entry_pathname(entry)))
            }
        }
        return paths
    }
}
