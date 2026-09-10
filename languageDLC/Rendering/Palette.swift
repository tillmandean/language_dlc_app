import UIKit

enum Palette {
    /// Assigned to selected languages by selection order.
    static let languageHues: [CGFloat] = [0.55, 0.08, 0.33, 0.80, 0.14, 0.92, 0.47, 0.65]

    static let ocean      = UIColor(white: 0.06, alpha: 1).cgColor
    static let lockedLand = UIColor(white: 0.20, alpha: 1).cgColor
    static let borders    = UIColor(white: 0.32, alpha: 1).cgColor

    /// Coverage 0...1 -> a bright, saturated fill. Low coverage stays dim and desaturated,
    /// so "unlocked" reads instantly on the globe.
    static func fill(hue: CGFloat, coverage: Double) -> CGColor {
        let c = CGFloat(min(max(coverage, 0), 1))
        let saturation = 0.35 + 0.55 * c
        let brightness = 0.30 + 0.62 * c
        return UIColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1).cgColor
    }

    static func hue(forSelectionIndex i: Int) -> CGFloat {
        languageHues[i % languageHues.count]
    }
}
