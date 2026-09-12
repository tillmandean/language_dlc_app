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
        let stored = UserDefaults.standard.array(forKey: key) as? [String]
        selected = stored ?? Self.seedFromDeviceLocale()
        // Property observers don't run for assignments made inside an initializer, so a seeded
        // selection has to be written back by hand. Persisting it — even when the seed came out
        // empty — is what makes this run exactly once per install: on every later launch `stored`
        // is non-nil, so deselecting everything stays deselected instead of silently refilling.
        if stored == nil { persist() }
        recompute()
    }

    /// What a brand-new install starts with: whichever of the user's own preferred languages this
    /// app knows about, in the order the system ranks them.
    ///
    /// A first launch otherwise opens on an entirely grey globe and a line of text telling you to
    /// go find a button — the app's whole pitch, *watch the world light up*, hidden behind a step
    /// the user hasn't been given a reason to take yet. Seeding costs them one tap per chip in the
    /// HUD to undo, and that undo sticks.
    private static func seedFromDeviceLocale() -> [String] {
        let known = DataStore.shared.languagesByCode
        var seed: [String] = []
        for identifier in Locale.preferredLanguages {
            // `languages.json` is keyed by bare CLDR codes ("en", "zh", "yue") with no script or
            // region subtags, so "en-GB" and "zh-Hans-CN" both have to be reduced first.
            guard let code = Locale(identifier: identifier).language.languageCode?.identifier,
                  known[code] != nil,
                  !seed.contains(code)
            else { continue }
            seed.append(code)
            if seed.count == maxSelected { break }
        }
        return seed
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
