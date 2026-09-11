import SwiftUI
import UIKit

/// Thin wrapper over `UIActivityViewController` — the system share sheet, for the rendered
/// share card (Phase 10.3).
struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Composites the current globe view and the DLC stats into a single shareable image.
enum ShareCardRenderer {
    private static let size = CGSize(width: 1080, height: 1350)
    private static let globeDiameter: CGFloat = 760

    static func makeCard(globe: UIImage, state: AppState) -> UIImage {
        let store = DataStore.shared
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            cg.setFillColor(Palette.ocean)
            cg.fill(CGRect(origin: .zero, size: size))

            drawGlobe(globe, in: cg)
            drawText(state: state, store: store)
        }
    }

    private static func drawGlobe(_ globe: UIImage, in cg: CGContext) {
        let rect = CGRect(x: (size.width - globeDiameter) / 2, y: 140,
                          width: globeDiameter, height: globeDiameter)
        cg.saveGState()
        cg.addEllipse(in: rect)
        cg.clip()
        // Center-crop the (likely non-square) snapshot into the circle.
        let side = min(globe.size.width, globe.size.height)
        let cropRect = CGRect(x: (globe.size.width - side) / 2, y: (globe.size.height - side) / 2,
                              width: side, height: side)
        if let cropped = globe.cgImage?.cropping(to: CGRect(x: cropRect.origin.x * globe.scale,
                                                             y: cropRect.origin.y * globe.scale,
                                                             width: cropRect.width * globe.scale,
                                                             height: cropRect.height * globe.scale)) {
            UIImage(cgImage: cropped).draw(in: rect)
        } else {
            globe.draw(in: rect)
        }
        cg.restoreGState()
    }

    private static func drawText(state: AppState, store: DataStore) {
        let textTop = 140 + globeDiameter + 60
        let title = "My Language DLC"
        let headline = "World unlocked: \(String(format: "%.1f", state.stats.fraction * 100))%"
        let secondary = "\(formatted(state.stats.peopleReached)) people · " +
            "\(state.stats.countriesAny) countries · official in \(state.stats.countriesOfficial)"

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 32, weight: .semibold),
            .foregroundColor: UIColor.white.withAlphaComponent(0.7),
        ]
        let headlineAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 56, weight: .bold),
            .foregroundColor: UIColor.white,
        ]
        let secondaryAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 28, weight: .regular),
            .foregroundColor: UIColor.white.withAlphaComponent(0.7),
        ]

        centeredText(title, attrs: titleAttrs, y: textTop)
        centeredText(headline, attrs: headlineAttrs, y: textTop + 50)
        centeredText(secondary, attrs: secondaryAttrs, y: textTop + 130)
        drawChips(for: state, store: store, y: textTop + 190)
    }

    private static func centeredText(_ text: String, attrs: [NSAttributedString.Key: Any], y: CGFloat) {
        let string = NSAttributedString(string: text, attributes: attrs)
        let textSize = string.size()
        string.draw(at: CGPoint(x: (size.width - textSize.width) / 2, y: y))
    }

    private static func drawChips(for state: AppState, store: DataStore, y: CGFloat) {
        let names = state.selected.compactMap { store.languagesByCode[$0]?.displayName }
        guard !names.isEmpty else { return }

        let font = UIFont.systemFont(ofSize: 26, weight: .medium)
        let padding: CGFloat = 20
        let spacing: CGFloat = 14
        let chipHeight: CGFloat = 56

        let widths = names.map { $0.size(withAttributes: [.font: font]).width + padding * 2 }
        let totalWidth = widths.reduce(0, +) + spacing * CGFloat(names.count - 1)
        var x = (size.width - totalWidth) / 2

        for (i, name) in names.enumerated() {
            let hue = Palette.hue(forSelectionIndex: i)
            let color = UIColor(hue: hue, saturation: 0.75, brightness: 0.9, alpha: 0.9)
            let rect = CGRect(x: x, y: y, width: widths[i], height: chipHeight)
            UIBezierPath(roundedRect: rect, cornerRadius: chipHeight / 2).addClip()
            color.setFill()
            UIRectFill(rect)
            UIGraphicsGetCurrentContext()?.resetClip()

            let textAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
            let textSize = name.size(withAttributes: textAttrs)
            name.draw(at: CGPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2),
                     withAttributes: textAttrs)
            x += widths[i] + spacing
        }
    }

    private static func formatted(_ n: Int) -> String {
        switch n {
        case 1_000_000_000...: return String(format: "%.1fB", Double(n) / 1e9)
        case 1_000_000...:     return String(format: "%.0fM", Double(n) / 1e6)
        case 1_000...:         return String(format: "%.0fK", Double(n) / 1e3)
        default:                return "\(n)"
        }
    }
}
