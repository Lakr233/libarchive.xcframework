import Foundation
import os

/// One launch, one file. The on-device viewer reads this back; the unified
/// log is a second copy for Console.app. Writes hop a serial queue so a
/// caller never waits on disk.
enum AppLog {
    enum Category: String, CaseIterable {
        case app
        case archive
        case job
    }

    enum Level: String {
        case verbose
        case info
        case warning
        case error
    }

    static let journalFileCount = 16

    static let journalDirectory: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Journal", isDirectory: true)
    }()

    private static let queue = DispatchQueue(label: "wiki.qaq.Archive.log", qos: .utility)
    private static let loggers: [Category: Logger] = Dictionary(
        uniqueKeysWithValues: Category.allCases.map {
            ($0, Logger(subsystem: "wiki.qaq.ArchiveViewerApp", category: $0.rawValue))
        }
    )

    private nonisolated(unsafe) static var handle: FileHandle?
    private nonisolated(unsafe) static var lastTag = ""
    static private(set) var currentFile: URL?

    static func start() {
        let manager = FileManager.default
        try? manager.createDirectory(at: journalDirectory, withIntermediateDirectories: true)
        let stamp = launchFormatter.string(from: Date())
        let name = "Archive_\(stamp)_\(UUID().uuidString.prefix(8)).log"
        let url = journalDirectory.appendingPathComponent(name)
        manager.createFile(atPath: url.path, contents: nil)
        currentFile = url
        handle = try? FileHandle(forWritingTo: url)
        retainLaunches()
        let bundle = Bundle.main.infoDictionary
        let version = bundle?["CFBundleShortVersionString"] as? String ?? "?"
        let build = bundle?["CFBundleVersion"] as? String ?? "?"
        info(.app, "Archive \(version) (\(build)) on \(ProcessInfo.processInfo.operatingSystemVersionString)")
    }

    static func verbose(_ category: Category, _ message: String) { write(.verbose, category, message) }
    static func info(_ category: Category, _ message: String) { write(.info, category, message) }
    static func warning(_ category: Category, _ message: String) { write(.warning, category, message) }
    static func error(_ category: Category, _ message: String) { write(.error, category, message) }

    private static func write(_ level: Level, _ category: Category, _ message: String) {
        let type: OSLogType = switch level {
        case .verbose: .debug
        case .info: .info
        case .warning: .default
        case .error: .error
        }
        loggers[category]?.log(level: type, "\(message, privacy: .public)")
        let stamp = lineFormatter.string(from: Date())
        queue.async {
            guard let handle else { return }
            var chunk = ""
            if lastTag != category.rawValue {
                chunk += "[\(category.rawValue)]\n"
                lastTag = category.rawValue
            }
            chunk += "* |\(level.rawValue)| \(stamp)| \(message)\n"
            if let data = chunk.data(using: .utf8) {
                try? handle.write(contentsOf: data)
            }
        }
    }

    private static func retainLaunches() {
        let launches = LogReader.launches()
        for extra in launches.dropFirst(journalFileCount) {
            try? FileManager.default.removeItem(at: extra.url)
        }
    }

    private static let launchFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()

    private static let lineFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()
}
