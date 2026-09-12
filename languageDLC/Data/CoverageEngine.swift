import Foundation

struct CountryCoverage {
    let territory: String
    let coverage: Double          // 0...1, share of population reached
    let dominantLanguage: String? // selected language with the highest pct here
    let dominantPct: Double       // 0...1
    let bestStatus: OfficialStatus?
}

struct WorldStats {
    let peopleReached: Int
    let worldPopulation: Int
    var fraction: Double { worldPopulation == 0 ? 0 : Double(peopleReached) / Double(worldPopulation) }
    let countriesMajority: Int   // countries where coverage >= 0.5
    let countriesAny: Int        // countries where coverage >= 0.05
    let countriesOfficial: Int   // countries where a selected language is official
}

enum CoverageEngine {

    /// Union of independent probabilities: 1 - Π(1 - p).
    /// Two languages at 60% and 50% in one country reach 80%, not 110%.
    static func coverage(for selected: [String], in store: DataStore) -> [String: CountryCoverage] {
        aggregate(selected: selected, store: store) { $0.territories }
    }

    /// Map-fill counterpart to `coverage(for:in:)`: identical except that a country whose curated
    /// regions carve into it contributes `restPct` — the share of the part those regions *don't*
    /// cover — instead of its whole-country `pct`. The curated regions are drawn on top of this
    /// fill, so using `pct` here would paint the remainder with an average of the regions
    /// covering it (Zurich at Switzerland's 39% French). Never feed this to `stats(_:in:)`:
    /// world coverage is a whole-country question and must use `coverage(for:in:)`.
    static func paintCoverage(for selected: [String], in store: DataStore) -> [String: CountryCoverage] {
        aggregate(selected: selected, store: store) {
            $0.territories.mapValues {
                LanguagePresence(pct: $0.restPct ?? $0.pct, status: $0.status)
            }
        }
    }

    /// Same union math as `coverage(for:in:)`, but over each language's curated sub-national
    /// presence (Phase 10.4) instead of its country-level one. Keyed by region id, e.g. "ES-CT" —
    /// these ids never collide with `store.territories`, so `stats(_:in:)` naturally ignores them
    /// rather than double-counting a region's people on top of its country.
    static func regionCoverage(for selected: [String], in store: DataStore) -> [String: CountryCoverage] {
        aggregate(selected: selected, store: store) { $0.regions ?? [:] }
    }

    private static func aggregate(selected: [String], store: DataStore,
                                  presences: (Language) -> [String: LanguagePresence])
        -> [String: CountryCoverage] {
        var result: [String: CountryCoverage] = [:]
        guard !selected.isEmpty else { return result }

        var notReached: [String: Double] = [:]   // territory -> Π(1 - p)
        var dominant: [String: (code: String, pct: Double)] = [:]
        var status: [String: OfficialStatus] = [:]

        for code in selected {
            guard let lang = store.languagesByCode[code] else { continue }
            for (terr, presence) in presences(lang) {
                let p = min(max(presence.pct / 100.0, 0), 1)
                notReached[terr] = (notReached[terr] ?? 1.0) * (1.0 - p)
                if p > (dominant[terr]?.pct ?? -1) { dominant[terr] = (code, p) }
                if let s = presence.status, rank(s) > rank(status[terr]) { status[terr] = s }
            }
        }

        for (terr, miss) in notReached {
            result[terr] = CountryCoverage(
                territory: terr,
                coverage: min(max(1.0 - miss, 0), 1),
                dominantLanguage: dominant[terr]?.code,
                dominantPct: dominant[terr]?.pct ?? 0,
                bestStatus: status[terr])
        }
        return result
    }

    static func stats(_ coverage: [String: CountryCoverage], in store: DataStore) -> WorldStats {
        let world = store.territories.values.reduce(0) { $0 + $1.population }
        var reached = 0, majority = 0, any = 0, official = 0
        for (terr, c) in coverage {
            guard let t = store.territories[terr] else { continue }
            reached += Int(Double(t.population) * c.coverage)
            if c.coverage >= 0.5  { majority += 1 }
            if c.coverage >= 0.05 { any += 1 }
            if c.bestStatus == .official || c.bestStatus == .deFactoOfficial { official += 1 }
        }
        return WorldStats(peopleReached: reached, worldPopulation: world,
                          countriesMajority: majority, countriesAny: any,
                          countriesOfficial: official)
    }

    /// Ranks every unselected language by how much world coverage it would add on top of the
    /// current selection — "learn this next" — instead of by raw speaker count.
    static func learningGoals(selected: [String], in store: DataStore, limit: Int = 5)
        -> [(language: Language, gain: Double)] {
        let baseline = stats(coverage(for: selected, in: store), in: store).fraction
        let selectedSet = Set(selected)
        var results: [(Language, Double)] = []
        for language in store.languages where !selectedSet.contains(language.code) {
            let withAdded = stats(coverage(for: selected + [language.code], in: store), in: store).fraction
            let gain = withAdded - baseline
            if gain > 0 { results.append((language, gain)) }
        }
        results.sort { $0.1 > $1.1 }
        return Array(results.prefix(limit))
    }

    private static func rank(_ s: OfficialStatus?) -> Int {
        switch s {
        case .official: return 4
        case .deFactoOfficial: return 3
        case .officialRegional: return 2
        case .officialMinority, .other: return 1
        case nil: return 0
        }
    }
}
