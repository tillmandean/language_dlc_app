import CoreGraphics
import Foundation
import Observation

@Observable
final class AppState {
    var selected: [String] = [] {          // ordered; order determines color
        didSet { persist(); recompute() }
    }
    private(set) var coverage: [String: CountryCoverage] = [:]
    private(set) var stats: WorldStats = WorldStats(peopleReached: 0, worldPopulation: 0,
                                                    countriesMajority: 0, countriesAny: 0,
                                                    countriesOfficial: 0)
    var focused: String?                    // tapped territory

    private let store = DataStore.shared
    private let key = "selectedLanguages"

    init() {
        selected = (UserDefaults.standard.array(forKey: key) as? [String]) ?? []
        recompute()
    }

    func toggle(_ code: String) {
        if let i = selected.firstIndex(of: code) { selected.remove(at: i) }
        else { selected.append(code) }
    }

    func hue(for code: String) -> CGFloat {
        Palette.hue(forSelectionIndex: selected.firstIndex(of: code) ?? 0)
    }

    /// territory -> fill color, ready for the rasterizer.
    func fillColors() -> [String: CGColor] {
        coverage.compactMapValues { c in
            guard let dom = c.dominantLanguage else { return nil }
            return Palette.fill(hue: hue(for: dom), coverage: c.coverage)
        }
    }

    private func recompute() {
        coverage = CoverageEngine.coverage(for: selected, in: store)
        stats = CoverageEngine.stats(coverage, in: store)
    }
    private func persist() { UserDefaults.standard.set(selected, forKey: key) }
}
