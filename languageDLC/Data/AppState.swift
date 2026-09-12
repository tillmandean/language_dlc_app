import CoreGraphics
import Foundation
import Observation

@Observable
final class AppState {
    var selected: [String] = [] {          // ordered; order determines color
        didSet { persist(); recompute() }
    }
    private(set) var coverage: [String: CountryCoverage] = [:]
    private(set) var paintCoverage: [String: CountryCoverage] = [:]
    private(set) var regionCoverage: [String: CountryCoverage] = [:]
    private(set) var stats: WorldStats = WorldStats(peopleReached: 0, worldPopulation: 0,
                                                    countriesMajority: 0, countriesAny: 0,
                                                    countriesOfficial: 0)
    var focused: String?                    // tapped territory

    /// The palette has this many distinct hues; selecting more would reuse a color.
    static let maxSelected = Palette.languageHues.count

    private let store = DataStore.shared
    private let key = "selectedLanguages"

    init() {
        selected = (UserDefaults.standard.array(forKey: key) as? [String]) ?? []
        recompute()
    }

    /// No-ops past `maxSelected` rather than growing the array — callers that want to tell the
    /// user why (e.g. the language picker) should check `selected.count` before calling this.
    func toggle(_ code: String) {
        if let i = selected.firstIndex(of: code) { selected.remove(at: i) }
        else if selected.count < Self.maxSelected { selected.append(code) }
    }

    func hue(for code: String) -> CGFloat {
        Palette.hue(forSelectionIndex: selected.firstIndex(of: code) ?? 0)
    }

    /// territory -> fill color, ready for the rasterizer. Uses `paintCoverage`, not `coverage`:
    /// where curated regions are drawn on top of a country, the country's own fill has to show
    /// the remainder those regions leave behind, not the whole-country average they're part of.
    func fillColors() -> [String: CGColor] {
        paintCoverage.compactMapValues { c in
            guard let dom = c.dominantLanguage else { return nil }
            return Palette.fill(hue: hue(for: dom), coverage: c.coverage)
        }
    }

    /// Same as `fillColors()` but for the curated sub-national regions (Phase 10.4). A region
    /// with no entry here is left undrawn, so its country's own color underneath keeps showing.
    func regionFillColors() -> [String: CGColor] {
        regionCoverage.compactMapValues { c in
            guard let dom = c.dominantLanguage else { return nil }
            return Palette.fill(hue: hue(for: dom), coverage: c.coverage)
        }
    }

    private func recompute() {
        coverage = CoverageEngine.coverage(for: selected, in: store)
        paintCoverage = CoverageEngine.paintCoverage(for: selected, in: store)
        regionCoverage = CoverageEngine.regionCoverage(for: selected, in: store)
        stats = CoverageEngine.stats(coverage, in: store)
    }
    private func persist() { UserDefaults.standard.set(selected, forKey: key) }
}
