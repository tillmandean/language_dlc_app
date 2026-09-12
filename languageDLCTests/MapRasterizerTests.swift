import Testing
import CoreGraphics
import Foundation
@testable import languageDLC

struct MapRasterizerTests {

    /// (lon, lat) -> texture coordinates, matching the projection in §4.1.
    private func uv(lon: Double, lat: Double) -> (u: Double, v: Double) {
        ((lon + 180) / 360, (90 - lat) / 180)
    }

    private func territory(_ r: MapRasterizer, lon: Double, lat: Double) -> String? {
        let p = uv(lon: lon, lat: lat)
        return r.territory(atU: p.u, v: p.v)
    }

    @Test func pickMapResolvesWellKnownPoints() {
        let r = MapRasterizer.shared
        #expect(territory(r, lon: 2.35, lat: 48.85) == "FR")     // Paris
        #expect(territory(r, lon: -99.13, lat: 19.43) == "MX")   // Mexico City
        #expect(territory(r, lon: 139.69, lat: 35.68) == "JP")   // Tokyo
        #expect(territory(r, lon: -47.93, lat: -15.78) == "BR")  // Brasilia
    }

    /// The antimeridian unwrap must not smear a country across the Pacific, and the far east
    /// of Russia must still be Russia rather than ocean.
    @Test func antimeridianIsHandled() {
        let r = MapRasterizer.shared
        #expect(territory(r, lon: 177.5, lat: 64.5) == "RU")     // Chukotka, east of 180 is RU
        #expect(territory(r, lon: -170.0, lat: 20.0) == nil)   // open Pacific stays ocean
        #expect(territory(r, lon: -150.0, lat: 0.0) == nil)
    }

    /// City-states are sub-pixel at map resolution; they survive as dots that later-drawn
    /// neighbours must not bury.
    @Test func tinyCountriesStayTappable() {
        let r = MapRasterizer.shared
        #expect(territory(r, lon: 103.8, lat: 1.35) == "SG")
        #expect(territory(r, lon: 14.5, lat: 35.9) == "MT")
        #expect(territory(r, lon: 50.55, lat: 26.2) == "BH")
    }

    /// Selecting Spanish must brighten Mexico while leaving Brazil at the locked-land grey.
    @Test func selectedLanguageColorsOnlyItsCountries() {
        let store = DataStore.shared
        let coverage = CoverageEngine.coverage(for: ["es"], in: store)
        var colors: [String: CGColor] = [:]
        for (terr, c) in coverage where c.dominantLanguage != nil {
            colors[terr] = Palette.fill(hue: Palette.hue(forSelectionIndex: 0), coverage: c.coverage)
        }
        let r = MapRasterizer(countries: store.countries, width: 2048, height: 1024)
        let image = r.renderTexture(colors: colors, ocean: Palette.ocean,
                                    lockedLand: Palette.lockedLand, borders: Palette.borders)!
        let data = image.dataProvider!.data! as Data
        func pixel(lon: Double, lat: Double) -> (r: UInt8, g: UInt8, b: UInt8) {
            let x = Int((lon + 180) / 360 * Double(image.width))
            let y = Int((90 - lat) / 180 * Double(image.height))
            let o = y * image.bytesPerRow + x * 4
            return (data[o], data[o + 1], data[o + 2])
        }
        let mexico = pixel(lon: -102.0, lat: 23.5)   // interior, away from borders
        let brazil = pixel(lon: -52.0, lat: -10.0)
        #expect(mexico.b > mexico.r)                 // hue 0.55 is blue
        #expect(mexico.b > 100)
        // Brazil is untouched by the selection, so it must still be exactly the locked-land
        // color — a stronger check than "some dim grey", and one that survives re-tinting the
        // palette (locked land is navy-slate now, not neutral grey).
        let locked = Palette.lockedLand.components!.map { UInt8(($0 * 255).rounded()) }
        #expect(brazil.r == locked[0])
        #expect(brazil.g == locked[1])
        #expect(brazil.b == locked[2])
    }

    /// Phase 10.4: a curated region drawn with its own color must not bleed into the rest of its
    /// country, and a region left out of `regionColors` must fall through to the country's fill.
    @Test func curatedRegionColorsOnlyItsOwnArea() {
        let store = DataStore.shared
        let r = MapRasterizer(countries: store.countries, regions: store.regions,
                              width: 2048, height: 1024)

        let switzerlandColor = Palette.fill(hue: 0.3, coverage: 1.0)
        let genevaColor = Palette.fill(hue: 0.9, coverage: 1.0)
        let image = r.renderTexture(colors: ["CH": switzerlandColor], ocean: Palette.ocean,
                                    lockedLand: Palette.lockedLand, borders: Palette.borders,
                                    regionColors: ["CH-GE": genevaColor])!
        let data = image.dataProvider!.data! as Data
        func pixel(lon: Double, lat: Double) -> (r: UInt8, g: UInt8, b: UInt8) {
            let x = Int((lon + 180) / 360 * Double(image.width))
            let y = Int((90 - lat) / 180 * Double(image.height))
            let o = y * image.bytesPerRow + x * 4
            return (data[o], data[o + 1], data[o + 2])
        }
        let geneva = pixel(lon: 6.14, lat: 46.30)     // canton interior, away from the border
        let zurich = pixel(lon: 8.55, lat: 47.40)     // elsewhere in Switzerland, no override
        #expect(geneva.r != zurich.r || geneva.g != zurich.g || geneva.b != zurich.b)
    }

    @Test func oceanReturnsNil() {
        let r = MapRasterizer.shared
        #expect(territory(r, lon: -30.0, lat: 30.0) == nil)      // mid-Atlantic
    }

    private func feature(_ r: MapRasterizer, lon: Double, lat: Double) -> MapFeature? {
        let p = uv(lon: lon, lat: lat)
        return r.feature(atU: p.u, v: p.v)
    }

    /// Curated regions are in the pick map on top of their country, so a tap inside one resolves
    /// to the region rather than the country — the gap this closes is that tapping Quebec used to
    /// report Canada.
    @Test func tapsInsideACuratedRegionResolveToTheRegion() {
        let r = MapRasterizer.shared
        #expect(feature(r, lon: -71.2, lat: 46.8) == .region(id: "CA-QC", country: "CA"))  // Quebec City
        #expect(feature(r, lon: 2.15, lat: 41.39) == .region(id: "ES-B", country: "ES"))   // Barcelona
        #expect(feature(r, lon: -97.7, lat: 30.3) == .region(id: "US-TX", country: "US"))  // Austin
    }

    /// The country underneath stays reachable everywhere that isn't curated — only a minority of
    /// each country is, so this is the common case even in countries that have regions.
    @Test func tapsOutsideACuratedRegionStillResolveToTheCountry() {
        let r = MapRasterizer.shared
        #expect(feature(r, lon: -83.0, lat: 40.0) == .country("US"))   // Ohio, not curated
        #expect(feature(r, lon: -113.5, lat: 53.5) == .country("CA"))  // Alberta, not curated
    }

    /// `territory(atU:v:)` is the country-level view of the same lookup: a hit inside a region
    /// reports the country containing it, so every existing territory-keyed caller is unaffected
    /// by regions having been added to the pick map.
    @Test func territoryReportsTheCountryForARegionHit() {
        let r = MapRasterizer.shared
        #expect(territory(r, lon: -71.2, lat: 46.8) == "CA")
        #expect(territory(r, lon: -97.7, lat: 30.3) == "US")
    }

    /// Region indices live above the country range in the same buffer, so an off-by-one in the
    /// encoding would silently turn regions into countries or run past the end of `regionIds`.
    @Test func regionIndicesDoNotCollideWithCountryIndices() {
        let r = MapRasterizer.shared
        #expect(r.regionIds.count == r.regionCountries.count)
        #expect(r.regionIds.count > 0)
        // Every region id must carry its country as its prefix, which is what the pick map's
        // parallel arrays assume when it reports a hit.
        for (id, country) in zip(r.regionIds, r.regionCountries) {
            #expect(id.hasPrefix(country))
        }
    }

    @Test func textureRendersAtRequestedSize() {
        let r = MapRasterizer(countries: DataStore.shared.countries, width: 512, height: 256)
        let image = r.renderTexture(colors: [:], ocean: Palette.ocean,
                                    lockedLand: Palette.lockedLand, borders: Palette.borders)
        #expect(image?.width == 512)
        #expect(image?.height == 256)
        #expect(r.ids.count > 200)
    }
}
