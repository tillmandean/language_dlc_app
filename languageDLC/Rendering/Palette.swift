import UIKit

enum Palette {
    /// Assigned to selected languages by selection order.
    static let languageHues: [CGFloat] = [0.55, 0.08, 0.33, 0.80, 0.14, 0.92, 0.47, 0.65]

    /// The map's fixed colors, matched to `Theme` so the globe and the chrome around it read as
    /// one surface. Kept at roughly the old greys' luminance — the point of locked land is that
    /// it stays dim next to an unlocked fill, and tinting it navy must not brighten it.
    /// A step lighter than `Theme.navy` on purpose. When the ocean matched the app background
    /// exactly, the sphere lost its silhouette wherever open water reached the limb and read as
    /// a flat cut-out; this keeps the globe sitting *on* the background.
    static let ocean      = UIColor(red: 0.027, green: 0.118, blue: 0.235, alpha: 1).cgColor  // #071E3C
    static let lockedLand = UIColor(red: 0.169, green: 0.227, blue: 0.322, alpha: 1).cgColor  // #2B3A52
    static let borders    = UIColor(red: 0.290, green: 0.373, blue: 0.502, alpha: 1).cgColor  // #4A5F80

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
