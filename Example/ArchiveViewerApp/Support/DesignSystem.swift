import SwiftUI
import UIKit

/// Spacing, type, and motion tokens. Call sites pick a named step rather than
/// inventing a point size; a new value that is not one of these is usually
/// the nearest existing one.
enum DS {
    enum Padding {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Radius {
        static let s: CGFloat = 6
        static let m: CGFloat = 12
        static let l: CGFloat = 16
    }

    enum Font {
        case title
        case control
        case controlEmphasis
        case body
        case label
        case labelEmphasis
        case detail
        case caption
        case captionEmphasis
        case symbol
        case heroSymbol
        case code
        case codeCaption

        var style: UIFont.TextStyle {
            switch self {
            case .title: .headline
            case .control, .controlEmphasis, .body: .body
            case .label, .labelEmphasis: .subheadline
            case .detail, .code: .footnote
            case .caption, .captionEmphasis: .caption1
            case .codeCaption: .caption2
            case .symbol: .title3
            case .heroSymbol: .largeTitle
            }
        }

        var weight: SwiftUI.Font.Weight {
            switch self {
            case .title, .controlEmphasis, .labelEmphasis, .captionEmphasis: .semibold
            case .control: .medium
            case .heroSymbol: .light
            default: .regular
            }
        }

        var design: SwiftUI.Font.Design {
            switch self {
            case .code, .codeCaption: .monospaced
            default: .default
            }
        }

        func resolved(scale: CGFloat, category: UIContentSizeCategory) -> SwiftUI.Font {
            let base: CGFloat = switch self {
            case .heroSymbol: 52
            default:
                UIFont.preferredFont(
                    forTextStyle: style,
                    compatibleWith: UITraitCollection(preferredContentSizeCategory: category)
                ).pointSize
            }
            return .system(size: base * scale, weight: weight, design: design)
        }
    }

    enum Motion {
        static let smooth = Animation.spring(response: 0.45, dampingFraction: 1.0)
        static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.9)
        static let structure = Animation.spring(response: 0.45, dampingFraction: 0.88)
    }
}

enum Palette {
    /// The one accent. Every filled control and progress ring uses this.
    static let accent = Color("AccentColor")
}

extension View {
    func font(_ role: DS.Font) -> some View {
        modifier(DSFontModifier(role: role))
    }
}

private struct DSFontModifier: ViewModifier {
    let role: DS.Font
    @Environment(\.interfaceTextScale) private var scale
    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        content.font(role.resolved(scale: scale, category: Self.category(for: typeSize)))
    }

    private static func category(for size: DynamicTypeSize) -> UIContentSizeCategory {
        switch size {
        case .xSmall: .extraSmall
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .xLarge: .extraLarge
        case .xxLarge: .extraExtraLarge
        case .xxxLarge: .extraExtraExtraLarge
        case .accessibility1: .accessibilityMedium
        case .accessibility2: .accessibilityLarge
        case .accessibility3: .accessibilityExtraLarge
        case .accessibility4: .accessibilityExtraExtraLarge
        case .accessibility5: .accessibilityExtraExtraExtraLarge
        @unknown default: .large
        }
    }
}
