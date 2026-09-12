import Testing
import Foundation
@testable import languageDLC

struct CoverageEngineTests {

    @Test func emptySelectionYieldsEmptyResults() {
        let store = DataStore.shared
        let coverage = CoverageEngine.coverage(for: [], in: store)
        #expect(coverage.isEmpty)

        let stats = CoverageEngine.stats(coverage, in: store)
        #expect(stats.peopleReached == 0)
        #expect(stats.countriesMajority == 0)
        #expect(stats.countriesAny == 0)
        #expect(stats.countriesOfficial == 0)
    }

    @Test func spanishCoversMexicoHeavilyAndNotJapan() {
        let store = DataStore.shared
        let coverage = CoverageEngine.coverage(for: ["es"], in: store)
        // CLDR spot check (PLAN.md §1.5): es in MX = 83%.
        let mx = coverage["MX"]
        #expect((mx?.coverage ?? 0) >= 0.75)

        let jp = coverage["JP"]
        #expect((jp?.coverage ?? 0) < 0.05)
    }

    @Test func unionMathCombinesTwoLanguagesCorrectly() {
        let store = makeSyntheticStore(
            languages: [
                ("A", ["XX": (pct: 60.0, status: nil)]),
                ("B", ["XX": (pct: 50.0, status: nil)]),
            ],
            territories: ["XX": 1_000_000])

        let coverage = CoverageEngine.coverage(for: ["A", "B"], in: store)
        let xx = coverage["XX"]
        #expect(xx != nil)
        #expect(abs((xx?.coverage ?? -1) - 0.8) < 1e-9)
    }

    @Test func englishReachesExpectedShareOfWorld() {
        let store = DataStore.shared
        let coverage = CoverageEngine.coverage(for: ["en"], in: store)
        let stats = CoverageEngine.stats(coverage, in: store)
        #expect(stats.fraction > 0.15)
        #expect(stats.fraction < 0.30)
    }

    @Test func englishChineseSpanishUnionNearExpectedShare() {
        let store = DataStore.shared
        let coverage = CoverageEngine.coverage(for: ["en", "zh", "es"], in: store)
        let stats = CoverageEngine.stats(coverage, in: store)
        #expect(stats.fraction > 0.38)
        #expect(stats.fraction < 0.50)
    }

    @Test func learningGoalsRanksHigherOverlapFirstAndExcludesSelected() {
        let store = makeSyntheticStore(
            languages: [
                ("A", ["XX": (pct: 90.0, status: nil), "YY": (pct: 90.0, status: nil)]),
                ("B", ["XX": (pct: 10.0, status: nil)]),
                ("C", ["XX": (pct: 90.0, status: nil)]),
            ],
            territories: ["XX": 1_000_000, "YY": 1_000_000])

        let goals = CoverageEngine.learningGoals(selected: [], in: store)
        #expect(goals.map(\.language.code) == ["A", "C", "B"])

        let afterC = CoverageEngine.learningGoals(selected: ["C"], in: store)
        #expect(!afterC.map(\.language.code).contains("C"))
        // B barely overlaps with C (both only touch XX, C already covers it), A still gains YY.
        #expect(afterC.first?.language.code == "A")
    }

    @Test func regionCoverageUsesUnionMathAndNeverLeaksIntoWorldStats() {
        let store = makeSyntheticStore(
            languages: [
                ("A", territories: ["XX": (pct: 60.0, status: nil)],
                      regions: ["XX-REG": (pct: 60.0, status: nil)]),
                ("B", territories: [:], regions: ["XX-REG": (pct: 50.0, status: nil)]),
            ],
            territories: ["XX": 1_000_000])

        let regionCoverage = CoverageEngine.regionCoverage(for: ["A", "B"], in: store)
        let reg = regionCoverage["XX-REG"]
        #expect(reg != nil)
        #expect(abs((reg?.coverage ?? -1) - 0.8) < 1e-9)

        // "XX-REG" isn't a territory key, so it must never contribute to world population stats
        // — otherwise a region's people would be double-counted on top of their country.
        let stats = CoverageEngine.stats(regionCoverage, in: store)
        #expect(stats.peopleReached == 0)
        #expect(stats.countriesAny == 0)
    }

    @Test func paintCoverageUsesRestPctWhileWorldStatsStayWholeCountry() {
        let store = DataStore(
            territories: ["XX": Territory(name: "", population: 1_000_000)],
            languages: [Language(code: "A", name: "A", speakers: 0,
                                 territories: ["XX": LanguagePresence(pct: 40, status: nil,
                                                                      restPct: 10)],
                                 regions: ["XX-REG": LanguagePresence(pct: 90, status: nil)])],
            countries: [])

        // The map fill for the part no curated region covers uses restPct...
        let paint = CoverageEngine.paintCoverage(for: ["A"], in: store)
        #expect(abs((paint["XX"]?.coverage ?? -1) - 0.10) < 1e-9)

        // ...while the country statistic and world coverage keep the whole-country pct, so
        // deriving a residual can never move the headline percentage.
        let coverage = CoverageEngine.coverage(for: ["A"], in: store)
        #expect(abs((coverage["XX"]?.coverage ?? -1) - 0.40) < 1e-9)
        #expect(CoverageEngine.stats(coverage, in: store).peopleReached == 400_000)

        // The carved-out region keeps its own figure, above both.
        let regions = CoverageEngine.regionCoverage(for: ["A"], in: store)
        #expect(abs((regions["XX-REG"]?.coverage ?? -1) - 0.90) < 1e-9)
    }

    /// The artifact this guards against: a canton with no French entry fell through to
    /// Switzerland's country fill and painted at the country-wide 39% — an average of the very
    /// cantons drawn on top of it, so Zurich read as substantially French-speaking.
    @Test func uncuratedRegionsPaintBelowTheirCuratedNeighbours() {
        let store = DataStore.shared
        let paint = CoverageEngine.paintCoverage(for: ["fr"], in: store)
        let regions = CoverageEngine.regionCoverage(for: ["fr"], in: store)
        let country = CoverageEngine.coverage(for: ["fr"], in: store)

        let vaud = regions["CH-VD"]?.coverage ?? 0
        let zurich = regions["CH-ZH"]?.coverage ?? 0
        #expect(zurich < vaud)                                  // below the French-speaking cantons
        #expect(zurich > 0)                                     // a residual, not a blanking
        #expect(zurich < country["CH"]?.coverage ?? 0)          // below the whole-country average
        // Switzerland's own fill is that same residual, so the cantons and the country agree.
        #expect(abs((paint["CH"]?.coverage ?? -1) - zurich) < 1e-9)
    }

    /// Builds a minimal in-memory DataStore via its test-only initializer.
    private func makeSyntheticStore(
        languages: [(code: String, territories: [String: (pct: Double, status: OfficialStatus?)],
                    regions: [String: (pct: Double, status: OfficialStatus?)])],
        territories: [String: Int]
    ) -> DataStore {
        let langs = languages.map { entry in
            Language(code: entry.code, name: entry.code, speakers: 0,
                      territories: entry.territories.mapValues { LanguagePresence(pct: $0.pct, status: $0.status) },
                      regions: entry.regions.isEmpty ? nil
                          : entry.regions.mapValues { LanguagePresence(pct: $0.pct, status: $0.status) })
        }
        let terrs = territories.mapValues { Territory(name: "", population: $0) }
        return DataStore(territories: terrs, languages: langs, countries: [])
    }

    /// Builds a minimal in-memory DataStore via its test-only initializer.
    private func makeSyntheticStore(
        languages: [(code: String, territories: [String: (pct: Double, status: OfficialStatus?)])],
        territories: [String: Int]
    ) -> DataStore {
        let langs = languages.map { entry in
            Language(code: entry.code, name: entry.code, speakers: 0,
                      territories: entry.territories.mapValues { LanguagePresence(pct: $0.pct, status: $0.status) })
        }
        let terrs = territories.mapValues { Territory(name: "", population: $0) }
        return DataStore(territories: terrs, languages: langs, countries: [])
    }
}
