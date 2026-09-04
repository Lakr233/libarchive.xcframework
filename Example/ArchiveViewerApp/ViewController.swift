import UniformTypeIdentifiers
import UIKit

/// Landing screen: a progress ring you tap to pick an archive, which then
/// fills as libarchive walks the file.
///
/// Laid out as one narrow column so a 13-inch iPad gets the same composition as
/// a phone rather than a lone control adrift in the middle of the display.
final class ViewController: UIViewController {
    private static let columnWidth: CGFloat = 400

    private let ring = ProgressRingView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let chooseButton = UIButton(type: .system)
    private let sampleButton = UIButton(type: .system)
    private let chooseCaption = UILabel()
    private let sampleCaption = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "libarchive"
        view.backgroundColor = .systemGroupedBackground

        ring.translatesAutoresizingMaskIntoConstraints = false
        ring.addTarget(self, action: #selector(chooseArchive), for: .touchUpInside)

        titleLabel.font = .preferredFont(forTextStyle: .title1)
            .withWeight(.bold, textStyle: .title1)
        titleLabel.textColor = .label

        detailLabel.font = .preferredFont(forTextStyle: .subheadline)
        detailLabel.textColor = .secondaryLabel

        for label in [titleLabel, detailLabel] {
            label.textAlignment = .center
            label.numberOfLines = 0
            label.adjustsFontForContentSizeCategory = true
        }

        configure(
            chooseButton,
            title: "Choose a File",
            symbol: "folder.badge.plus",
            prominent: true,
            action: #selector(chooseArchive)
        )
        configure(
            sampleButton,
            title: "Open a Sample Archive",
            symbol: "shippingbox",
            prominent: false,
            action: #selector(openSample)
        )

        caption(chooseCaption, "libarchive detects the format from the contents, so any file is worth a try.")
        caption(sampleCaption, "Writes a small .tar.xz inside this app, then reads it back.")

        // The ring keeps its own size instead of being stretched to the column,
        // so it needs a row of its own to be centred in.
        let ringRow = UIView()
        ringRow.addSubview(ring)

        let column = UIStackView(arrangedSubviews: [
            ringRow,
            titleLabel,
            detailLabel,
            chooseButton,
            chooseCaption,
            sampleButton,
            sampleCaption,
            makeNoteCard(),
        ])
        column.axis = .vertical
        column.alignment = .fill
        column.spacing = 8
        column.setCustomSpacing(28, after: ringRow)
        column.setCustomSpacing(6, after: titleLabel)
        column.setCustomSpacing(32, after: detailLabel)
        column.setCustomSpacing(10, after: chooseButton)
        column.setCustomSpacing(20, after: chooseCaption)
        column.setCustomSpacing(10, after: sampleButton)
        column.setCustomSpacing(36, after: sampleCaption)
        column.translatesAutoresizingMaskIntoConstraints = false

        // A scroll view so the column survives Dynamic Type at XL and a landscape
        // phone; the canvas keeps it optically centred whenever it does fit.
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.contentInsetAdjustmentBehavior = .always
        view.addSubview(scrollView)

        let canvas = UIView()
        canvas.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(canvas)
        canvas.addSubview(column)

        let content = scrollView.contentLayoutGuide
        let frame = scrollView.frameLayoutGuide
        let flexibleWidth = column.widthAnchor.constraint(equalTo: canvas.widthAnchor, constant: -40)
        flexibleWidth.priority = .defaultHigh

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            canvas.topAnchor.constraint(equalTo: content.topAnchor),
            canvas.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            canvas.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            canvas.widthAnchor.constraint(equalTo: frame.widthAnchor),
            canvas.heightAnchor.constraint(greaterThanOrEqualTo: frame.heightAnchor),

            column.centerXAnchor.constraint(equalTo: canvas.centerXAnchor),
            column.centerYAnchor.constraint(equalTo: canvas.centerYAnchor),
            column.topAnchor.constraint(greaterThanOrEqualTo: canvas.topAnchor, constant: 32),
            column.bottomAnchor.constraint(lessThanOrEqualTo: canvas.bottomAnchor, constant: -32),
            column.widthAnchor.constraint(lessThanOrEqualToConstant: Self.columnWidth),
            flexibleWidth,

            ring.widthAnchor.constraint(equalToConstant: 132),
            ring.heightAnchor.constraint(equalTo: ring.widthAnchor),
            ring.centerXAnchor.constraint(equalTo: ringRow.centerXAnchor),
            ring.topAnchor.constraint(equalTo: ringRow.topAnchor),
            ring.bottomAnchor.constraint(equalTo: ringRow.bottomAnchor),
        ])

        setIdle()
    }

    /// Writes a sample archive into the app's temporary directory and lists it,
    /// so the app has something to open on a device with no files of its own.
    @objc private func openSample() {
        do {
            scan(try SampleArchive.make())
        } catch {
            fail(error, title: "Couldn't build the sample")
        }
    }

    @objc private func chooseArchive() {
        // Every file, not just the extensions the system recognises as
        // archives. libarchive sniffs content rather than names, so it opens
        // plenty of files the system has no type for -- and a file it cannot
        // read reports that far more usefully than a greyed-out picker row.
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: false)
        picker.delegate = self
        present(picker, animated: true)
    }

    private func scan(_ url: URL) {
        setScanning(url.lastPathComponent)

        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                try ArchiveReader.listEntries(at: url) { fraction in
                    DispatchQueue.main.async {
                        self.ring.phase = .reading(fraction)
                    }
                }
            }

            DispatchQueue.main.async {
                switch result {
                case let .success(entries):
                    self.ring.phase = .finished
                    self.titleLabel.text = "Done"
                    // A beat on the completed ring, so the walk visibly ends
                    // rather than cutting straight to the push.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self.setIdle()
                        self.show(
                            ArchiveListViewController(name: url.lastPathComponent, entries: entries),
                            sender: self
                        )
                    }
                case let .failure(error):
                    self.fail(error, title: "Couldn't read \(url.lastPathComponent)")
                }
            }
        }
    }

    private func setIdle() {
        ring.phase = .idle
        setControls(enabled: true)
        titleLabel.text = "Open an archive"
        detailLabel.text = "Read what is inside without extracting anything."
        detailLabel.textColor = .secondaryLabel
    }

    private func setScanning(_ name: String) {
        ring.phase = .reading(0)
        setControls(enabled: false)
        titleLabel.text = "Reading"
        detailLabel.text = name
        detailLabel.textColor = .secondaryLabel
    }

    /// Failures land on the screen the file was chosen from rather than in an
    /// alert: the reason belongs next to the control you would use to retry.
    private func fail(_ error: Error, title: String) {
        ring.phase = .failed
        setControls(enabled: true)
        titleLabel.text = title
        detailLabel.text = error.localizedDescription
        detailLabel.textColor = .systemRed
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    private func setControls(enabled: Bool) {
        ring.isEnabled = enabled
        chooseButton.isEnabled = enabled
        sampleButton.isEnabled = enabled
        for caption in [chooseCaption, sampleCaption] {
            caption.alpha = enabled ? 1 : 0.4
        }
    }

    private func configure(
        _ button: UIButton,
        title: String,
        symbol: String,
        prominent: Bool,
        action: Selector
    ) {
        var configuration: UIButton.Configuration = prominent ? .filled() : .gray()
        configuration.title = title
        configuration.image = UIImage(systemName: symbol)
        configuration.imagePadding = 8
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 14,
            leading: 20,
            bottom: 14,
            trailing: 20
        )
        configuration.titleTextAttributesTransformer = .init { attributes in
            var attributes = attributes
            attributes.font = .preferredFont(forTextStyle: .body)
                .withWeight(.semibold, textStyle: .body)
            return attributes
        }
        button.configuration = configuration
        button.addTarget(self, action: action, for: .touchUpInside)
        button.configurationUpdateHandler = { button in
            button.alpha = button.isHighlighted ? 0.85 : 1
        }
    }

    private func caption(_ label: UILabel, _ text: String) {
        label.text = text
        label.font = .preferredFont(forTextStyle: .caption1)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
    }

    private func makeNoteCard() -> UIView {
        let icon = UIImageView(image: UIImage(systemName: "eye"))
        icon.tintColor = .secondaryLabel
        icon.contentMode = .scaleAspectFit
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let heading = UILabel()
        heading.text = "Nothing is extracted"
        heading.font = .preferredFont(forTextStyle: .subheadline)
            .withWeight(.semibold, textStyle: .subheadline)
        heading.adjustsFontForContentSizeCategory = true

        let body = UILabel()
        body.text = "Only entry headers are read — from zip, tar, 7z, rar, iso, xz, gzip, bzip2, zstd, cpio and more."
        body.font = .preferredFont(forTextStyle: .footnote)
        body.textColor = .secondaryLabel
        body.numberOfLines = 0
        body.adjustsFontForContentSizeCategory = true

        let text = UIStackView(arrangedSubviews: [heading, body])
        text.axis = .vertical
        text.spacing = 3

        let row = UIStackView(arrangedSubviews: [icon, text])
        row.axis = .horizontal
        row.alignment = .top
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 14,
            leading: 16,
            bottom: 14,
            trailing: 16
        )

        let card = UIView()
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = 16
        card.layer.cornerCurve = .continuous
        card.addSubview(row)

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: card.topAnchor),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            icon.firstBaselineAnchor.constraint(equalTo: heading.firstBaselineAnchor),
        ])
        return card
    }
}

extension ViewController: UIDocumentPickerDelegate {
    func documentPicker(_: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        scan(url)
    }
}
