import SwiftUI

struct AlertRequest: Identifiable, Equatable {
    let id: UUID
    let title: String.LocalizationValue
    let message: String.LocalizationValue
    let specs: [Spec]

    struct Spec: Equatable {
        let title: String.LocalizationValue
        let kind: AlertButtonStyle.Kind
        let id: UUID

        init(
            _ title: String.LocalizationValue,
            kind: AlertButtonStyle.Kind = .normal
        ) {
            self.title = title
            self.kind = kind
            self.id = UUID()
        }

        static func == (lhs: Spec, rhs: Spec) -> Bool {
            lhs.id == rhs.id
        }
    }

    /// Handlers live outside Equatable comparison; they run after dismiss.
    let handlers: [UUID: () -> Void]

    init(
        title: String.LocalizationValue,
        message: String.LocalizationValue,
        actions: [(String.LocalizationValue, AlertButtonStyle.Kind, () -> Void)]
    ) {
        let id = UUID()
        self.id = id
        self.title = title
        self.message = message
        var specs: [Spec] = []
        var handlers: [UUID: () -> Void] = [:]
        for action in actions {
            let spec = Spec(action.0, kind: action.1)
            specs.append(spec)
            handlers[spec.id] = action.2
        }
        self.specs = specs
        self.handlers = handlers
    }

    static func == (lhs: AlertRequest, rhs: AlertRequest) -> Bool {
        lhs.id == rhs.id
    }
}

/// Presents `AlertViewController` from the window root so a request raised
/// under a sheet still lands above it.
struct AlertPresenter: ViewModifier {
    @Binding var request: AlertRequest?
    @State private var window: UIWindow?
    @State private var presented: AlertViewController?

    func body(content: Content) -> some View {
        content
            .background(WindowReader(window: $window))
            .onChange(of: request?.id) { _, _ in present() }
            .onChange(of: window != nil) { _, _ in present() }
    }

    private func present() {
        guard let request, let window, presented == nil else { return }
        let finish: () -> Void = {
            presented = nil
            if self.request?.id == request.id {
                self.request = nil
            }
        }
        let actions = request.specs.map { spec in
            AlertAction(spec.title, kind: spec.kind) {
                finish()
                request.handlers[spec.id]?()
            }
        }
        let alert = AlertViewController(
            title: request.title,
            message: request.message,
            actions: actions
        )
        alert.onDismissUnanswered = finish
        presented = alert
        alert.present(in: window)
    }
}

extension View {
    func archiveAlerts(_ request: Binding<AlertRequest?>) -> some View {
        modifier(AlertPresenter(request: request))
    }
}
