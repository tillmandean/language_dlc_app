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
