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
        var result: [String: CountryCoverage] = [:]
        guard !selected.isEmpty else { return result }

        var notReached: [String: Double] = [:]   // territory -> Π(1 - p)
        var dominant: [String: (code: String, pct: Double)] = [:]
        var status: [String: OfficialStatus] = [:]

        for code in selected {
            guard let lang = store.languagesByCode[code] else { continue }
            for (terr, presence) in lang.territories {
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
