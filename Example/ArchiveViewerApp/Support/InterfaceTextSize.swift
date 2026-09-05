import SwiftUI

/// Steps around the platform size. Zero is the system default; each step is
/// ten percent. A multiplier, not a `dynamicTypeSize` override, so Dynamic
/// Type still applies on top.
enum InterfaceTextSize {
    static let key = "Interface.textSizeStep"
    static let steps = -4 ... 8

    static func scale(step: Int) -> CGFloat {
        pow(1.1, CGFloat(min(max(step, steps.lowerBound), steps.upperBound)))
    }
}

private struct InterfaceTextSizeModifier: ViewModifier {
    @AppStorage(InterfaceTextSize.key) private var step = 0

    func body(content: Content) -> some View {
        content
            .font(DS.Font.body)
            .environment(\.interfaceTextScale, InterfaceTextSize.scale(step: step))
    }
}

extension EnvironmentValues {
    @Entry var interfaceTextScale: CGFloat = 1
}

extension View {
    func interfaceTextSize() -> some View {
        modifier(InterfaceTextSizeModifier())
    }
}
