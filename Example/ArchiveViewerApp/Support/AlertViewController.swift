import SwiftUI
import UIKit

/// Replacement for `UIAlertController` (and SwiftUI `.alert`): the same
/// `AlertCardView`, presented over a dimmed pane with a cross-dissolve.
/// Every action dismisses the alert before its handler runs.
final class AlertViewController: OverlayPanelController {
    private let alertTitle: String
    private let alertMessage: String
    private let actions: [AlertAction]
    private var hasAnswered = false

    var onDismissUnanswered: (() -> Void)?

    init(
        title: String.LocalizationValue,
        message: String.LocalizationValue,
        actions: [AlertAction]
    ) {
        alertTitle = String(localized: title)
        alertMessage = String(localized: message)
        self.actions = actions
        onDismissUnanswered = actions.first { $0.kind == .normal }?.handler
        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let dismissing = actions.map { action in
            AlertAction(verbatim: action.title, kind: action.kind) { [weak self] in
                self?.answer(action)
            }
        }
        install(AlertPane(title: alertTitle, message: alertMessage, actions: dismissing))
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard !hasAnswered, isBeingDismissed || presentingViewController == nil else { return }
        hasAnswered = true
        onDismissUnanswered?()
    }

    private func answer(_ action: AlertAction) {
        guard !hasAnswered else { return }
        hasAnswered = true
        dismiss(animated: true, completion: action.handler)
    }
}

private struct AlertPane: View {
    let title: String
    let message: String
    let actions: [AlertAction]

    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
            AlertCardView(title: title, message: message, actions: actions)
                .padding(DS.Padding.l)
        }
    }
}
