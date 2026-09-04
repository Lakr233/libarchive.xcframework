import Foundation

enum Formatters {
    static let bytes: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    static let date: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()
}

enum EntrySymbol {
    static func name(for entry: ArchiveOperations.Entry) -> String {
        guard !entry.isDirectory else { return "folder.fill" }
        return switch entry.path.split(separator: ".").last?.lowercased() {
        case "c", "h", "cpp", "m", "swift", "py", "rb", "js", "ts", "go", "rs", "sh",
             "json", "yml", "yaml", "toml", "xml", "plist":
            "curlybraces"
        case "md", "txt", "rst", "log", "cfg", "conf":
            "doc.text"
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "svg", "tiff":
            "photo"
        case "zip", "tar", "gz", "xz", "bz2", "zst", "7z", "rar":
            "shippingbox"
        default:
            "doc"
        }
    }
}
