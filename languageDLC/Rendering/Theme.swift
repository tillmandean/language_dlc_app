import SwiftUI

/// The app's chrome colors, sampled from the logo: a near-black navy ground, a lighter navy for
/// anything that sits on top of it, and the logo's light blue as the single accent.
///
/// Language fills are deliberately *not* here — those come from `Palette`, which spreads them
/// across the whole hue wheel so eight selections stay distinguishable on the globe. This is the
/// fixed part of the palette; `Palette` is the variable part.
enum Theme {
    /// #021029 — the logo's own background, so the splash logo sits on it seamlessly.
    static let navy        = Color(red: 0.008, green: 0.063, blue: 0.161)
    /// #010818 — a shade under `navy`, for the bottom of background gradients.
    static let navyDeep    = Color(red: 0.004, green: 0.031, blue: 0.094)
    /// #0C2144 — raised surfaces: HUD, list rows, sheet backgrounds.
    static let navySurface = Color(red: 0.047, green: 0.129, blue: 0.267)
    /// #2EA6FF — the logo's "DLC" blue. Also the asset-catalog accent color.
    static let sky         = Color(red: 0.180, green: 0.651, blue: 1.000)
    /// #23C9FF — the brighter end of the logo's gradient, for highlights.
    static let skyBright   = Color(red: 0.137, green: 0.788, blue: 1.000)

    /// The ground under every screen. Slightly lighter at the top so the globe reads as lit.
    static var background: LinearGradient {
        LinearGradient(colors: [navy, navyDeep], startPoint: .top, endPoint: .bottom)
    }

    /// Hairline used to separate surfaces from the navy behind them.
    static let hairline = Color(red: 0.180, green: 0.651, blue: 1.000).opacity(0.18)
}

extension View {
    /// The shared look for the app's sheet lists: navy ground instead of the system's near-black,
    /// and a nav bar in the same navy so the sheet reads as one surface.
    ///
    /// Goes on the `List`. Pair it with `navyRows()` on each `Section` — row backgrounds don't
    /// inherit from the list, only from the section they're in.
    func navyList() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .toolbarBackground(Theme.navy, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }

    /// Row fill for a `Section` inside a `navyList()`: a shade above the ground, so rows still
    /// lift off it the way the system's default grey does against black.
    func navyRows() -> some View {
        listRowBackground(Theme.navySurface)
    }
}
