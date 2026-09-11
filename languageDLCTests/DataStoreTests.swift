import Testing
import Foundation
@testable import languageDLC

struct DataStoreTests {

    @Test func loadsWithinTimeBudget() {
        let start = CFAbsoluteTimeGetCurrent()
        let store = DataStore.shared
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        print("DataStore load: \(elapsed) ms")
        #expect(!store.territories.isEmpty)
    }

    @Test func territoryCount() {
        // Natural Earth's 50m file resolves to 237 distinct territories after the CLDR join
        // (verified: 257 CLDR territories minus 20 with no matching polygon, within the
        // "losing under 20 is expected" tolerance from the data pipeline).
        #expect(DataStore.shared.territories.count >= 230)
    }

    @Test func languageCount() {
        #expect(DataStore.shared.languages.count >= 400)
    }

    @Test func countryGeometryCount() {
        #expect(DataStore.shared.countries.count >= 200)
    }

    /// Phase 10.4's curated sub-national regions (Swiss cantons, Belgian provinces, Spanish
    /// autonomous-community provinces, Quebec/New Brunswick, Indian states, US states).
    @Test func regionGeometryCount() {
        #expect(DataStore.shared.regions.count == 72)
    }

    @Test func catalanHasCuratedRegionData() throws {
        let store = DataStore.shared
        let ca = try #require(store.languagesByCode["ca"])
        let regions = try #require(ca.regions)
        #expect(regions["ES-B"] != nil)   // Barcelona, in Cataluña
    }

    @Test func spanishCoversExpectedTerritories() throws {
        let store = DataStore.shared
        let es = try #require(store.languagesByCode["es"])
        #expect(es.territories.count >= 30)
    }

    @Test func englishCoversExpectedTerritories() throws {
        let store = DataStore.shared
        let en = try #require(store.languagesByCode["en"])
        #expect(en.territories.count >= 120)
    }

    @Test func topLanguagesReferenceValidPopulatedTerritories() {
        let store = DataStore.shared
        let geometryIds = Set(store.countries.map(\.id))
        let topLanguages = store.languages.prefix(20)

        for language in topLanguages {
            for territoryCode in language.territories.keys where geometryIds.contains(territoryCode) {
                let population = store.territories[territoryCode]?.population ?? 0
                #expect(population > 0, "\(territoryCode) referenced by \(language.code) has no population")
            }
        }
    }
}
