import UIKit

/// One row of an archive listing: what the entry is called, where it sits, and
/// how big it is.
///
/// The name leads because that is what you scan for; the directory it came from
/// stays underneath in a monospaced face, so a path still reads as a path.
final class ArchiveEntryCell: UITableViewCell {
    static let reuseIdentifier = "entry"

    private let icon = UIImageView()
    private let nameLabel = UILabel()
    private let pathLabel = UILabel()
    private let sizeLabel = UILabel()
    private let dateLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        icon.contentMode = .center
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            textStyle: .body,
            scale: .large
        )
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.setContentCompressionResistancePriority(.required, for: .horizontal)

        nameLabel.font = .preferredFont(forTextStyle: .body)
        nameLabel.lineBreakMode = .byTruncatingMiddle

        pathLabel.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(
            for: .monospacedSystemFont(ofSize: 12, weight: .regular)
        )
        pathLabel.textColor = .secondaryLabel
        pathLabel.lineBreakMode = .byTruncatingHead

        sizeLabel.font = .preferredFont(forTextStyle: .subheadline).monospacedDigits
        sizeLabel.textColor = .secondaryLabel
        sizeLabel.textAlignment = .right

        dateLabel.font = .preferredFont(forTextStyle: .caption1).monospacedDigits
        dateLabel.textColor = .tertiaryLabel
        dateLabel.textAlignment = .right

        for label in [nameLabel, pathLabel, sizeLabel, dateLabel] {
            label.adjustsFontForContentSizeCategory = true
        }

        let leading = UIStackView(arrangedSubviews: [nameLabel, pathLabel])
        leading.axis = .vertical
        leading.spacing = 2

        let trailing = UIStackView(arrangedSubviews: [sizeLabel, dateLabel])
        trailing.axis = .vertical
        trailing.alignment = .trailing
        trailing.spacing = 2
        trailing.setContentHuggingPriority(.required, for: .horizontal)
        trailing.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [icon, leading, trailing])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)

        let margins = contentView.layoutMarginsGuide
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            row.topAnchor.constraint(equalTo: margins.topAnchor),
            row.bottomAnchor.constraint(equalTo: margins.bottomAnchor),
            icon.widthAnchor.constraint(equalToConstant: Self.iconColumn),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Separators start under the name rather than under the icon, so the
        // icon column reads as one continuous edge down the list.
        separatorInset = UIEdgeInsets(
            top: 0,
            left: layoutMargins.left + Self.iconColumn + 12,
            bottom: 0,
            right: 0
        )
    }

    private static let iconColumn: CGFloat = 26

    func configure(with entry: ArchiveReader.Entry, byteFormatter: ByteCountFormatter, dateFormatter: DateFormatter) {
        let components = entry.path.split(separator: "/", omittingEmptySubsequences: true)
        nameLabel.text = components.last.map(String.init) ?? entry.path

        let parent = components.dropLast().joined(separator: "/")
        pathLabel.text = parent
        pathLabel.isHidden = parent.isEmpty

        icon.image = UIImage(systemName: Self.symbolName(for: entry))
        icon.tintColor = entry.isDirectory ? .tintColor : .secondaryLabel

        sizeLabel.text = entry.isDirectory
            ? "Folder"
            : byteFormatter.string(fromByteCount: entry.size)
        dateLabel.text = entry.modified.map(dateFormatter.string(from:))
        dateLabel.isHidden = entry.modified == nil
    }

    /// A handful of extension families, so a listing is scannable by shape
    /// rather than only by name. Anything unrecognised stays a plain document.
    private static func symbolName(for entry: ArchiveReader.Entry) -> String {
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
