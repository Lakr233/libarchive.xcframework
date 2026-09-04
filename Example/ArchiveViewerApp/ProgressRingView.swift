import UIKit

/// A circular determinate progress indicator. Tapping it is how the app starts.
///
/// The centre carries the state rather than a caption below it, so the ring
/// reads as one object: an affordance when idle, a percentage while reading,
/// an outcome when it stops.
final class ProgressRingView: UIControl {
    enum Phase: Equatable {
        case idle
        case reading(Double)
        case finished
        case failed
    }

    var phase: Phase = .idle {
        didSet {
            guard phase != oldValue else { return }
            apply(phase, animated: window != nil)
        }
    }

    private let trackLayer = CAShapeLayer()
    private let fillLayer = CAShapeLayer()
    private let symbolView = UIImageView()
    private let percentLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)

        for layer in [trackLayer, fillLayer] {
            layer.fillColor = UIColor.clear.cgColor
            layer.lineWidth = 10
            layer.lineCap = .round
            self.layer.addSublayer(layer)
        }
        trackLayer.strokeColor = UIColor.secondarySystemFill.cgColor
        fillLayer.strokeColor = UIColor.tintColor.cgColor
        fillLayer.strokeEnd = 0

        symbolView.translatesAutoresizingMaskIntoConstraints = false
        symbolView.contentMode = .scaleAspectFit
        symbolView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 40,
            weight: .regular
        )
        addSubview(symbolView)

        // Tabular figures: the percentage changes many times a second and must
        // not shuffle sideways while it counts.
        percentLabel.translatesAutoresizingMaskIntoConstraints = false
        percentLabel.font = .monospacedDigitSystemFont(ofSize: 30, weight: .semibold)
        percentLabel.textColor = .label
        percentLabel.textAlignment = .center
        percentLabel.alpha = 0
        addSubview(percentLabel)

        NSLayoutConstraint.activate([
            symbolView.centerXAnchor.constraint(equalTo: centerXAnchor),
            symbolView.centerYAnchor.constraint(equalTo: centerYAnchor),
            percentLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            percentLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        apply(.idle, animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let inset = trackLayer.lineWidth / 2
        let path = UIBezierPath(
            arcCenter: CGPoint(x: bounds.midX, y: bounds.midY),
            radius: min(bounds.width, bounds.height) / 2 - inset,
            startAngle: -.pi / 2,
            endAngle: .pi * 1.5,
            clockwise: true
        )
        for layer in [trackLayer, fillLayer] {
            layer.frame = bounds
            layer.path = path.cgPath
        }
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        // CGColor does not resolve dynamically, so the ring has to repaint itself
        // when the appearance flips.
        trackLayer.strokeColor = UIColor.secondarySystemFill.cgColor
        fillLayer.strokeColor = strokeColor(for: phase).cgColor
    }

    private func apply(_ phase: Phase, animated: Bool) {
        fillLayer.strokeColor = strokeColor(for: phase).cgColor

        let showsPercent: Bool
        switch phase {
        case .idle:
            symbolView.image = UIImage(systemName: "archivebox")
            symbolView.tintColor = .tintColor
            showsPercent = false
        case let .reading(fraction):
            percentLabel.text = Self.percentFormatter.string(
                from: NSNumber(value: max(0, min(1, fraction)))
            )
            showsPercent = true
        case .finished:
            symbolView.image = UIImage(systemName: "checkmark")
            symbolView.tintColor = .tintColor
            showsPercent = false
        case .failed:
            symbolView.image = UIImage(systemName: "exclamationmark.triangle")
            symbolView.tintColor = .systemRed
            showsPercent = false
        }

        setStroke(fraction(of: phase), animated: animated)

        let swap = {
            self.percentLabel.alpha = showsPercent ? 1 : 0
            self.symbolView.alpha = showsPercent ? 0 : 1
        }
        animated ? UIView.animate(withDuration: 0.2, animations: swap) : swap()
    }

    /// `strokeEnd` animates implicitly, which is what smooths the bursts of
    /// progress libarchive reports; resets have to opt out of that or the ring
    /// unwinds backwards on screen.
    private func setStroke(_ value: CGFloat, animated: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(0.25)
        fillLayer.strokeEnd = value
        CATransaction.commit()
    }

    private func fraction(of phase: Phase) -> CGFloat {
        switch phase {
        case .idle: 0
        case let .reading(fraction): CGFloat(max(0, min(1, fraction)))
        case .finished, .failed: 1
        }
    }

    private func strokeColor(for phase: Phase) -> UIColor {
        phase == .failed ? .systemRed : .tintColor
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.12, delay: 0, options: .curveEaseOut) {
                self.transform = self.isHighlighted
                    ? CGAffineTransform(scaleX: 0.96, y: 0.96)
                    : .identity
                self.alpha = self.isHighlighted ? 0.7 : 1
            }
        }
    }

    private static let percentFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}
