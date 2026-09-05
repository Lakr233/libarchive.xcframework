import Foundation

struct LogEntry: Identifiable, Hashable {
    enum Level: String, CaseIterable, Hashable {
        case verbose
        case info
        case warning
        case error
    }

    let id: Int
    let timestamp: String
    let level: Level
    let category: String
    var message: String
    var text: String
}

struct LogLaunch: Identifiable, Hashable {
    let url: URL
    let date: Date?
    var id: URL { url }
}

struct LogDocument {
    var entries: [LogEntry] = []
    var categories: [String] = []
    var location = ""
    var unreadable = false
    var readAt = Date()
}

enum LogReader {
    static let maximumByteCount = 2 << 20

    static func launches() -> [LogLaunch] {
        let directory = AppLog.journalDirectory
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return []
        }
        return names
            .filter { $0.hasPrefix("Archive_") && $0.hasSuffix(".log") }
            .map { LogLaunch(url: directory.appendingPathComponent($0), date: launchDate(of: $0)) }
            .sorted { a, b in
                switch (a.date, b.date) {
                case let (x?, y?): x > y
                case (_?, nil): true
                case (nil, _?): false
                case (nil, nil): a.url.lastPathComponent > b.url.lastPathComponent
                }
            }
    }

    private static func launchDate(of name: String) -> Date? {
        let parts = name.dropFirst("Archive_".count).split(separator: "_")
        guard parts.count >= 2 else { return nil }
        return AppLogDate.launch.date(from: "\(parts[0])_\(parts[1])")
    }

    static func deleteOlderLaunches() {
        let current = AppLog.currentFile?.standardizedFileURL
        for launch in launches() where launch.url.standardizedFileURL != current {
            try? FileManager.default.removeItem(at: launch.url)
        }
    }

    static func read(launch: URL? = nil) -> LogDocument {
        let url = launch ?? AppLog.currentFile
        var document = LogDocument()
        document.location = url?.path ?? AppLog.journalDirectory.path
        guard let url, let text = tail(of: url) else {
            document.unreadable = true
            return document
        }
        document.entries = parseJournal(text)
        document.categories = Array(Set(document.entries.map(\.category))).sorted()
        return document
    }

    static func exportFile(launch: URL? = nil) -> URL? {
        guard let url = launch ?? AppLog.currentFile else { return nil }
        let name = "Archive-\(url.deletingPathExtension().lastPathComponent).log"
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.copyItem(at: url, to: destination)
            return destination
        } catch {
            return nil
        }
    }

    private static func tail(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        var trimmed = false
        if size > UInt64(maximumByteCount) {
            trimmed = true
            try? handle.seek(toOffset: size - UInt64(maximumByteCount))
        } else {
            try? handle.seek(toOffset: 0)
        }
        guard let data = try? handle.readToEnd() else { return nil }
        var text = String(decoding: data, as: UTF8.self)
        if trimmed, let newline = text.firstIndex(of: "\n") {
            text = String(text[text.index(after: newline)...])
        }
        return text
    }

    /// Dog's line shape: `[tag]` then `* |level| stamp| message`.
    static func parseJournal(_ text: String) -> [LogEntry] {
        var entries: [LogEntry] = []
        var tag = "?"
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.isEmpty { continue }
            if line.hasPrefix("["), line.hasSuffix("]"), line.count > 2 {
                tag = String(line.dropFirst().dropLast())
                continue
            }
            if let entry = parseJournalLine(line, tag: tag, id: entries.count) {
                entries.append(entry)
            } else if entries.isEmpty {
                entries.append(LogEntry(
                    id: 0,
                    timestamp: "",
                    level: .info,
                    category: tag,
                    message: String(line),
                    text: String(line)
                ))
            } else {
                entries[entries.count - 1].message += "\n" + line
                entries[entries.count - 1].text += "\n" + line
            }
        }
        return entries
    }

    private static func parseJournalLine(_ line: Substring, tag: String, id: Int) -> LogEntry? {
        guard line.hasPrefix("* |") else { return nil }
        let afterMarker = line.dropFirst(3)
        guard let levelEnd = afterMarker.firstIndex(of: "|") else { return nil }
        let level = LogEntry.Level(rawValue: String(afterMarker[..<levelEnd])) ?? .info
        let afterLevel = afterMarker[afterMarker.index(after: levelEnd)...].drop(while: { $0 == " " })
        guard let stampEnd = afterLevel.firstIndex(of: "|") else { return nil }
        let stamp = String(afterLevel[..<stampEnd]).replacingOccurrences(of: "_", with: " ")
        let message = afterLevel[afterLevel.index(after: stampEnd)...].drop(while: { $0 == " " })
        return LogEntry(
            id: id,
            timestamp: stamp,
            level: level,
            category: tag,
            message: String(message),
            text: String(line)
        )
    }
}

private enum AppLogDate {
    static let launch: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()
}
