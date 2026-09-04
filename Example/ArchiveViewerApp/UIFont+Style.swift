import UIKit

extension UIFont {
    /// A weighted face that still scales with Dynamic Type, which
    /// `preferredFont(forTextStyle:)` alone cannot give you.
    func withWeight(_ weight: UIFont.Weight, textStyle: UIFont.TextStyle) -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: weight],
        ])
        return UIFontMetrics(forTextStyle: textStyle).scaledFont(
            for: UIFont(descriptor: descriptor, size: pointSize)
        )
    }

    /// Figures that keep their column as numbers change.
    var monospacedDigits: UIFont {
        let descriptor = fontDescriptor.addingAttributes([
            .featureSettings: [[
                UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector,
            ]],
        ])
        return UIFont(descriptor: descriptor, size: 0)
    }
}
