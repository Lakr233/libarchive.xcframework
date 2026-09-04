import SwiftUI
import UIKit

extension View {
    @ViewBuilder
    func barGlass(in shape: some Shape, interactive: Bool = true) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
                .geometryGroup()
        } else {
            background(.ultraThinMaterial, in: shape)
                .geometryGroup()
        }
    }

    /// Alert cards and overlay panes: Liquid Glass on iOS 26, material below.
    @ViewBuilder
    func cardGlass(in shape: some Shape) -> some View {
        if #available(iOS 26.0, *) {
            clipShape(shape)
                .glassEffect(.regular, in: shape)
        } else {
            clipShape(shape)
                .background(.regularMaterial)
                .background(Color(UIColor.systemBackground).opacity(0.5))
                .clipShape(shape)
        }
    }
}
