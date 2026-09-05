import UIKit

@MainActor
enum ShareSheet {
    /// Waits for a menu's dismissal; presenting into it leaves a dead sheet.
    static func present(_ url: URL, in window: UIWindow?) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            presentNow(url, in: window)
        }
    }

    static func presentNow(_ url: URL, in window: UIWindow?) {
        guard let window, var top = window.rootViewController else { return }
        while let presented = top.presentedViewController {
            top = presented
        }
        let controller = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )
        if let popover = controller.popoverPresentationController {
            popover.sourceView = window
            popover.sourceRect = CGRect(
                x: window.bounds.midX,
                y: window.bounds.midY,
                width: 1,
                height: 1
            )
            popover.permittedArrowDirections = []
        }
        top.present(controller, animated: true)
    }
}
