import SwiftUI
import UIKit

/// Full-window SwiftUI pane with a cross-dissolve. `.overFullScreen` keeps
/// the presenter mounted under the dim, so the tab bar does not re-lay out
/// the way a sheet does on the way in.
class OverlayPanelController: UIViewController {
    init() {
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }

    func install(_ pane: some View) {
        let host = UIHostingController(rootView: pane.interfaceTextSize())
        host.view.backgroundColor = .clear
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        host.didMove(toParent: self)
    }

    /// Walks to the front-most presentation context so an alert raised under
    /// a sheet lands above the sheet instead of failing on a covered presenter.
    func present(in window: UIWindow?) {
        guard var presenter = window?.rootViewController else { return }
        while let presented = presenter.presentedViewController {
            guard !presented.isBeingDismissed else {
                if let coordinator = presented.transitionCoordinator {
                    coordinator.animate(alongsideTransition: nil) { [weak self] _ in
                        self?.present(in: window)
                    }
                    return
                }
                break
            }
            presenter = presented
        }
        presenter.present(self, animated: true)
    }
}
