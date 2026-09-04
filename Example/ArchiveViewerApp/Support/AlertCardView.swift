import SwiftUI
import UIKit

/// One action on an alert card. Titles arrive as `String.LocalizationValue`,
/// so a call site's string literal stays a localization key — the same
/// contract SwiftUI's `.alert` gave those literals. A `String` variable will
/// not compile; an unlocalized title has to say so with `verbatim:`.
struct AlertAction: Identifiable {
    let id = UUID()
    let title: String
    let kind: AlertButtonStyle.Kind
    let handler: () -> Void

    init(
        _ title: String.LocalizationValue,
        kind: AlertButtonStyle.Kind = .normal,
        handler: @escaping () -> Void = {}
    ) {
        self.init(verbatim: String(localized: title), kind: kind, handler: handler)
    }

    init(
        verbatim title: String,
        kind: AlertButtonStyle.Kind = .normal,
        handler: @escaping () -> Void = {}
    ) {
        self.title = title
        self.kind = kind
        self.handler = handler
    }
}

extension Array where Element == AlertAction {
    var defaultAction: AlertAction? {
        if count == 1 { return first }
        return last { $0.kind == .destructive }
            ?? last { $0.kind == .accent }
    }
}

/// Lakr233/AlertController as SwiftUI: centered glass card, app-icon header,
/// emphasized action filled with its tint. Shown inline and presented by
/// `AlertViewController` so both stay the same card.
struct AlertCardView: View {
    let title: String
    let message: String
    let actions: [AlertAction]
    var claimsFirstResponder = true

    var body: some View {
        VStack(spacing: DS.Padding.l) {
            Image("AlertIcon")
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))

            Text(title)
                .font(DS.Font.title)
                .multilineTextAlignment(.center)

            if !message.isEmpty {
                Text(message)
                    .font(DS.Font.detail)
                    .multilineTextAlignment(.center)
                    .lineLimit(6)
            }

            HStack(spacing: DS.Padding.s) {
                ForEach(actions) { action in
                    Button(action: action.handler) {
                        Text(action.title)
                    }
                    .buttonStyle(AlertButtonStyle(kind: action.kind))
                }
            }
        }
        .padding(DS.Padding.l)
        .frame(maxWidth: 350)
        .cardGlass(in: RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous))
        .fixedSize(horizontal: false, vertical: true)
        .background {
            if claimsFirstResponder {
                AlertFirstResponder {
                    actions.defaultAction?.handler()
                }
            }
        }
    }
}

private struct AlertFirstResponder: UIViewRepresentable {
    var onReturn: () -> Void

    func makeUIView(context _: Context) -> ClaimView {
        let view = ClaimView()
        view.onReturn = onReturn
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: ClaimView, context _: Context) {
        view.onReturn = onReturn
        view.claimIfNeeded()
    }

    static func dismantleUIView(_ view: ClaimView, coordinator _: ()) {
        view.wantsFirstResponder = false
        if view.isFirstResponder {
            _ = view.resignFirstResponder()
        }
    }

    final class ClaimView: UIView {
        var onReturn: () -> Void = {}
        var wantsFirstResponder = true
        private var isHandlingReturn = false

        override var canBecomeFirstResponder: Bool { wantsFirstResponder }

        override var keyCommands: [UIKeyCommand]? {
            let command = UIKeyCommand(
                input: "\r",
                modifierFlags: [],
                action: #selector(performDefaultAction)
            )
            command.wantsPriorityOverSystemBehavior = true
            return [command]
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil {
                claimIfNeeded()
            }
        }

        func claimIfNeeded() {
            guard wantsFirstResponder, !isFirstResponder, isInFrontmostPresentation else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.wantsFirstResponder, self.isInFrontmostPresentation else { return }
                _ = self.becomeFirstResponder()
            }
        }

        private var isInFrontmostPresentation: Bool {
            guard let window, var top = window.rootViewController else { return false }
            while let presented = top.presentedViewController, !presented.isBeingDismissed {
                top = presented
            }
            guard let topView = top.viewIfLoaded else { return false }
            return isDescendant(of: topView)
        }

        override func resignFirstResponder() -> Bool {
            let resigned = super.resignFirstResponder()
            if resigned, wantsFirstResponder {
                claimIfNeeded()
            }
            return resigned
        }

        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            if consumeReturn(presses) { return }
            super.pressesBegan(presses, with: event)
        }

        override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            if isUnmodifiedReturn(presses) { return }
            super.pressesEnded(presses, with: event)
        }

        @objc private func performDefaultAction() {
            fireReturn()
        }

        private func consumeReturn(_ presses: Set<UIPress>) -> Bool {
            guard isUnmodifiedReturn(presses) else { return false }
            fireReturn()
            return true
        }

        private func isUnmodifiedReturn(_ presses: Set<UIPress>) -> Bool {
            presses.contains { press in
                guard let key = press.key else { return false }
                let extras = key.modifierFlags.subtracting([.numericPad, .alphaShift])
                guard extras.isEmpty else { return false }
                return key.keyCode == .keyboardReturnOrEnter || key.keyCode == .keypadEnter
            }
        }

        private func fireReturn() {
            guard !isHandlingReturn else { return }
            isHandlingReturn = true
            onReturn()
            DispatchQueue.main.async { [weak self] in
                self?.isHandlingReturn = false
            }
        }
    }
}

struct AlertButtonStyle: ButtonStyle {
    enum Kind {
        case normal
        case accent
        case destructive
    }

    let kind: Kind

    private var tint: Color {
        kind == .destructive ? .red : .accentColor
    }

    private var isFilled: Bool {
        kind != .normal
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(isFilled ? DS.Font.controlEmphasis : DS.Font.body)
            .foregroundColor(isFilled ? .white : .accentColor)
            .padding(DS.Padding.s)
            .frame(maxWidth: .infinity)
            .background(isFilled ? tint : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                    .strokeBorder(tint, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
