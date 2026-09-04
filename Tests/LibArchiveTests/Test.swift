import LibArchive
import XCTest

/// Properties of the build itself. Format and filter coverage lives in
/// `FormatCoverageTests`.
final class LibArchiveTests: XCTestCase {
    func testVersion() {
        let version = String(cString: archive_version_string())
        XCTAssertTrue(version.hasPrefix("libarchive "), version)
    }

    /// Every optional dependency this package promises, named by libarchive
    /// itself. A backend silently dropped at configure time disappears from
    /// here rather than failing anything else.
    func testEveryBundledDependencyIsLinked() {
        let details = String(cString: archive_version_details())
        for dependency in ["zlib/", "bz2lib/", "liblzma/", "libzstd/", "liblz4/", "libxml2/"] {
            XCTAssertTrue(details.contains(dependency), "\(dependency) missing from: \(details)")
        }
    }

    /// The external-program filters are built without fork/posix_spawn, so
    /// their two helpers come from a stub in this repo. If that stub ever goes
    /// missing the library stops linking; if it ever starts succeeding, a
    /// sandboxed app would be spawning a binary it cannot spawn.
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
}
