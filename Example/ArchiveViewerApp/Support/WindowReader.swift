import SwiftUI
import UIKit

/// Reports the `UIWindow` the attachment point lands in, for UIKit
/// presentations (`AlertViewController`, the share sheet).
struct WindowReader: UIViewRepresentable {
    @Binding var window: UIWindow?

    func makeUIView(context _: Context) -> Probe {
        let probe = Probe()
        probe.isUserInteractionEnabled = false
        probe.onWindow = { window = $0 }
        return probe
    }

    func updateUIView(_ probe: Probe, context _: Context) {
        probe.onWindow = { window = $0 }
    }

    final class Probe: UIView {
        var onWindow: (UIWindow?) -> Void = { _ in }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window else { return }
            DispatchQueue.main.async { [self] in
                onWindow(window)
            }
        }
    }
}
