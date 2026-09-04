import UIKit

/// The contents of one archive. Nothing is extracted -- these are headers.
///
/// A summary card leads, because the first questions about an archive are how
/// much is in it and how big it is, and neither is answerable by scrolling.
final class ArchiveListViewController: UIViewController {
    private static let columnWidth: CGFloat = 620

    private enum Section: Int, CaseIterable {
        case summary
        case entries
    }

    private let entries: [ArchiveReader.Entry]
    private var visible: [ArchiveReader.Entry]
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let searchController = UISearchController(searchResultsController: nil)

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        // Archives are usually built recently enough that "Today" carries more
        // than the numerals do.
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    init(name: String, entries: [ArchiveReader.Entry]) {
        self.entries = entries
        visible = entries
        super.init(nibName: nil, bundle: nil)
        title = name
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemGroupedBackground

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.keyboardDismissMode = .onDrag
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60
        tableView.register(ArchiveEntryCell.self, forCellReuseIdentifier: ArchiveEntryCell.reuseIdentifier)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "summary")
        view.addSubview(tableView)

        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Filter paths"
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false

        // Inset-grouped rows would otherwise stretch the full width of an iPad,
        // leaving a line of text with nowhere for the eye to land.
        let flexibleWidth = tableView.widthAnchor.constraint(equalTo: view.widthAnchor)
        flexibleWidth.priority = .defaultLow

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            tableView.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor),
            tableView.widthAnchor.constraint(lessThanOrEqualToConstant: Self.columnWidth),
            flexibleWidth,
        ])

        // Also settles the empty-archive state, which no search ever triggers.
        updateSearchResults(for: searchController)
    }

    private var totalSize: Int64 {
        entries.reduce(0) { $0 + ($1.isDirectory ? 0 : max(0, $1.size)) }
    }

    private func makeSummaryCell() -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "summary")!
        cell.selectionStyle = .none
        cell.contentView.subviews.forEach { $0.removeFromSuperview() }

        let files = entries.filter { !$0.isDirectory }.count
        let stats = [
            ("Files", files.formatted()),
            ("Folders", (entries.count - files).formatted()),
            ("Unpacked", Self.byteFormatter.string(fromByteCount: totalSize)),
        ]

        let row = UIStackView(arrangedSubviews: stats.map(makeStat))
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.alignment = .top
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(row)

        let margins = cell.contentView.layoutMarginsGuide
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            row.topAnchor.constraint(equalTo: margins.topAnchor, constant: 6),
            row.bottomAnchor.constraint(equalTo: margins.bottomAnchor, constant: -6),
        ])
        return cell
    }

    private func makeStat(_ caption: String, _ value: String) -> UIView {
        let captionLabel = UILabel()
        captionLabel.attributedText = NSAttributedString(
            string: caption.uppercased(),
            attributes: [.kern: 0.6]
        )
        captionLabel.font = .preferredFont(forTextStyle: .caption2)
            .withWeight(.semibold, textStyle: .caption2)
        captionLabel.textColor = .secondaryLabel
        captionLabel.numberOfLines = 2

        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = .preferredFont(forTextStyle: .title3)
            .withWeight(.semibold, textStyle: .title3)
            .monospacedDigits
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.7

        for label in [captionLabel, valueLabel] {
            label.adjustsFontForContentSizeCategory = true
            label.lineBreakMode = .byTruncatingTail
        }

        let stack = UIStackView(arrangedSubviews: [captionLabel, valueLabel])
        stack.axis = .vertical
        stack.spacing = 2
        return stack
    }
}

extension ArchiveListViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in _: UITableView) -> Int {
        Section.allCases.count
    }

    func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        Section(rawValue: section) == .summary ? 1 : visible.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        // No header when nothing matches: the empty message already says so.
        guard Section(rawValue: section) == .entries, !visible.isEmpty else { return nil }
        if visible.count == entries.count {
            return entries.count == 1 ? "1 entry" : "\(entries.count.formatted()) entries"
        }
        return visible.count == 1 ? "1 match" : "\(visible.count.formatted()) matches"
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard Section(rawValue: indexPath.section) == .entries else {
            return makeSummaryCell()
        }

        let cell = tableView.dequeueReusableCell(
            withIdentifier: ArchiveEntryCell.reuseIdentifier,
            for: indexPath
        ) as! ArchiveEntryCell
        cell.configure(
            with: visible[indexPath.row],
            byteFormatter: Self.byteFormatter,
            dateFormatter: Self.dateFormatter
        )
        cell.selectionStyle = .none
        return cell
    }
}

extension ArchiveListViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        let query = searchController.searchBar.text?
            .trimmingCharacters(in: .whitespaces) ?? ""
        visible = query.isEmpty
            ? entries
            : entries.filter { $0.path.localizedCaseInsensitiveContains(query) }

        tableView.reloadSections(IndexSet(integer: Section.entries.rawValue), with: .none)
        tableView.backgroundView = visible.isEmpty ? makeNoMatchesView(for: query) : nil
    }

    private func makeNoMatchesView(for query: String) -> UIView {
        let label = UILabel()
        label.text = query.isEmpty
            ? "This archive has no entries."
            : "No entry matches “\(query)”."
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true

        let container = UIView()
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -40),
            label.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor, constant: -64),
        ])
        return container
    }
}
