import LibArchive
import XCTest

/// Exercises every format and filter this build claims to support.
///
/// Anything libarchive can also write is round-tripped rather than shipped as a
/// fixture: a generated archive proves the writer and the reader agree, and it
/// cannot drift out of date. Fixtures exist only for the formats libarchive
/// reads but cannot produce.
final class FormatCoverageTests: XCTestCase {
    private static let files = [
        ("alpha.txt", "alpha contents\n"),
        ("beta.txt", "beta contents\n"),
    ]

    private var paths: [String] { Self.files.map(\.0) }
    private var bodies: [String] { Self.files.map(\.1) }

    // MARK: - Containers

    func testEveryWritableContainerRoundTrips() throws {
        let containers: [(String, (OpaquePointer?) -> Int32)] = [
            ("pax", archive_write_set_format_pax),
            ("pax_restricted", archive_write_set_format_pax_restricted),
            ("ustar", archive_write_set_format_ustar),
            ("v7tar", archive_write_set_format_v7tar),
            ("gnutar", archive_write_set_format_gnutar),
            ("cpio", archive_write_set_format_cpio),
            ("cpio_bin", archive_write_set_format_cpio_bin),
            ("cpio_newc", archive_write_set_format_cpio_newc),
            ("cpio_odc", archive_write_set_format_cpio_odc),
            ("cpio_pwb", archive_write_set_format_cpio_pwb),
            ("zip", archive_write_set_format_zip),
            ("7zip", archive_write_set_format_7zip),
            ("xar", archive_write_set_format_xar),
            ("warc", archive_write_set_format_warc),
            ("ar_bsd", archive_write_set_format_ar_bsd),
            ("ar_svr4", archive_write_set_format_ar_svr4),
        ]

        for (name, setFormat) in containers {
            let archived = try write(format: setFormat)
            let read = try read(archived)
            XCTAssertEqual(read.paths, paths, name)
            XCTAssertEqual(read.bodies, bodies, name)
        }
    }

    /// ISO 9660 always emits a root directory entry, and its minimum image is
    /// ~350 KB of mostly padding whatever you put in it.
    func testISO9660RoundTrips() throws {
        let archived = try write(format: archive_write_set_format_iso9660, capacity: 4 << 20)
        let read = try read(archived)
        XCTAssertEqual(read.paths, ["."] + paths)
        XCTAssertEqual(Array(read.bodies.dropFirst()), bodies)
    }

    /// mtree describes a tree, it does not carry the bytes, so only the paths
    /// come back. The classic dialect also emits the root entry.
    func testMetadataOnlyFormatsRoundTripPaths() throws {
        XCTAssertEqual(
            try read(write(format: archive_write_set_format_mtree)).paths,
            paths.map { "./\($0)" }
        )
        XCTAssertEqual(
            try read(write(format: archive_write_set_format_mtree_classic)).paths,
            ["."] + paths
        )
    }

    /// raw is a single unnamed blob: libarchive rejects a second entry, and the
    /// name it reports on the way back is always "data".
    func testRawFormatRoundTripsOneEntry() throws {
        let payload = "raw payload\n"
        let archived = try write(format: archive_write_set_format_raw, files: [("ignored", payload)])
        let read = try read(archived, formats: archive_read_support_format_raw)
        XCTAssertEqual(read.paths, ["data"])
        XCTAssertEqual(read.bodies, [payload])
    }

    /// shar emits a shell script. It is a real output format with no reader,
    /// so the most that can be asserted is that it produced a script.
    func testShellArchivesAreWriteOnly() throws {
        for (name, setFormat) in [
            ("shar", archive_write_set_format_shar),
            ("shar_dump", archive_write_set_format_shar_dump),
        ] as [(String, (OpaquePointer?) -> Int32)] {
            let script = String(decoding: try write(format: setFormat), as: UTF8.self)
            XCTAssertTrue(script.contains("alpha.txt"), name)
            XCTAssertTrue(script.contains("beta.txt"), name)
        }
    }

    // MARK: - Filters

    func testEveryWritableFilterRoundTrips() throws {
        let filters: [(String, (OpaquePointer?) -> Int32)] = [
            ("none", archive_write_add_filter_none),
            ("gzip", archive_write_add_filter_gzip),
            ("bzip2", archive_write_add_filter_bzip2),
            ("xz", archive_write_add_filter_xz),
            ("lzma", archive_write_add_filter_lzma),
            ("lzip", archive_write_add_filter_lzip),
            ("zstd", archive_write_add_filter_zstd),
            ("lz4", archive_write_add_filter_lz4),
            ("compress", archive_write_add_filter_compress),
            ("uuencode", archive_write_add_filter_uuencode),
            ("b64encode", archive_write_add_filter_b64encode),
        ]

        for (name, addFilter) in filters {
            let archived = try write(format: archive_write_set_format_pax_restricted, filter: addFilter)
            let read = try read(archived)
            XCTAssertEqual(read.paths, paths, name)
            XCTAssertEqual(read.bodies, bodies, name)
        }
    }

    /// The three filters libarchive implements only by spawning a helper. This
    /// build has no way to spawn one, so they must refuse at registration
    /// rather than fail somewhere less obvious later.
    func testHelperBasedFiltersRefuseToRegister() throws {
        for (name, addFilter) in [
            ("lzop", archive_write_add_filter_lzop),
            ("lrzip", archive_write_add_filter_lrzip),
            ("grzip", archive_write_add_filter_grzip),
        ] as [(String, (OpaquePointer?) -> Int32)] {
            let archive = try XCTUnwrap(archive_write_new())
            defer { archive_write_free(archive) }
            XCTAssertNotEqual(addFilter(archive), ARCHIVE_OK, name)
        }
    }

    // MARK: - Formats libarchive reads but cannot write

    func testReadOnlyFormatFixtures() throws {
        let expected: [(file: String, format: String, paths: [String])] = [
            ("rar4.rar", "RAR", ["test.txt", "testlink", "testdir/test.txt", "testdir", "testemptydir"]),
            ("rar5.rar", "RAR5", ["helloworld.txt"]),
            ("cab.cab", "CAB", ["empty", "dir1/file1", "dir2/file2"]),
            ("lha.lzh", "lha", ["dir/", "dir2/", "dir2/symlink1", "dir2/symlink2", "file1", "file2"]),
            // The rpm filter peels the package header off a gzipped cpio.
            ("cpio.rpm", "cpio", ["./etc/file1", "./etc/file2", "./etc/file3"]),
        ]

        for expectation in expected {
            let url = try XCTUnwrap(
                Bundle.module.url(forResource: "Fixtures/\(expectation.file)", withExtension: nil),
                expectation.file
            )
            let read = try read(Data(contentsOf: url))
            XCTAssertEqual(read.paths, expectation.paths, expectation.file)
            XCTAssertTrue(
                read.format.localizedCaseInsensitiveContains(expectation.format),
                "\(expectation.file): reported \(read.format)"
            )
        }
    }

    // MARK: - Helpers

    private func write(
        format setFormat: (OpaquePointer?) -> Int32,
        filter addFilter: ((OpaquePointer?) -> Int32)? = nil,
        files: [(String, String)] = FormatCoverageTests.files,
        capacity: Int = 256 << 10
    ) throws -> Data {
        let archive = try XCTUnwrap(archive_write_new())

        // libarchive keeps both pointers until the write is closed, so neither
        // can come from an inout conversion. Freeing them is declared first so
        // it runs last: closing the writer still needs the buffer.
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: capacity, alignment: 1)
        let used = UnsafeMutablePointer<Int>.allocate(capacity: 1)
        used.initialize(to: 0)
        defer {
            buffer.deallocate()
            used.deallocate()
        }
        defer { archive_write_free(archive) }

        if let addFilter {
            XCTAssertEqual(addFilter(archive), ARCHIVE_OK)
        }
        XCTAssertEqual(setFormat(archive), ARCHIVE_OK)
        XCTAssertEqual(archive_write_open_memory(archive, buffer, capacity, used), ARCHIVE_OK)

        for (path, contents) in files {
            let entry = try XCTUnwrap(archive_entry_new())
            defer { archive_entry_free(entry) }

            let bytes = Array(contents.utf8)
            archive_entry_set_pathname(entry, path)
            archive_entry_set_size(entry, Int64(bytes.count))
            archive_entry_set_filetype(entry, 0o100_000) // AE_IFREG
            archive_entry_set_perm(entry, 0o644)
            // warc refuses an entry with no timestamp.
            archive_entry_set_mtime(entry, 1_700_000_000, 0)

            XCTAssertEqual(archive_write_header(archive, entry), ARCHIVE_OK, path)
            XCTAssertEqual(archive_write_data(archive, bytes, bytes.count), bytes.count, path)
        }

        XCTAssertEqual(archive_write_close(archive), ARCHIVE_OK)
        return Data(bytes: buffer, count: used.pointee)
    }

    private func read(
        _ data: Data,
        formats supportFormats: (OpaquePointer?) -> Int32 = archive_read_support_format_all
    ) throws -> (paths: [String], bodies: [String], format: String) {
        let archive = try XCTUnwrap(archive_read_new())
        defer { archive_read_free(archive) }

        XCTAssertEqual(archive_read_support_filter_all(archive), ARCHIVE_OK)
        XCTAssertEqual(supportFormats(archive), ARCHIVE_OK)

        var paths: [String] = []
        var bodies: [String] = []
        var format = ""

        try data.withUnsafeBytes { raw in
            XCTAssertEqual(archive_read_open_memory(archive, raw.baseAddress, raw.count), ARCHIVE_OK)

            var entry: OpaquePointer?
            while archive_read_next_header(archive, &entry) == ARCHIVE_OK {
                paths.append(String(cString: try XCTUnwrap(archive_entry_pathname(entry))))

                var chunk = [UInt8](repeating: 0, count: 4096)
                let count = archive_read_data(archive, &chunk, chunk.count)
                bodies.append(count > 0 ? String(decoding: chunk[0 ..< count], as: UTF8.self) : "")
            }
            // Nil until a header has been read, and for formats that never
            // name themselves.
            format = archive_format_name(archive).map { String(cString: $0) } ?? ""
        }

        return (paths, bodies, format)
    }
}
