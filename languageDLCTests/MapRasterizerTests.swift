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
        #expect(brazil.r == brazil.b)                // grey
        #expect(brazil.r < 80)
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

    @Test func textureRendersAtRequestedSize() {
        let r = MapRasterizer(countries: DataStore.shared.countries, width: 512, height: 256)
        let image = r.renderTexture(colors: [:], ocean: Palette.ocean,
                                    lockedLand: Palette.lockedLand, borders: Palette.borders)
        #expect(image?.width == 512)
        #expect(image?.height == 256)
        #expect(r.ids.count > 200)
    }
}
