import Foundation

/// Everything loaded from the bundle. Built once, then read-only.
final class DataStore {
    let territories: [String: Territory]
    let languages: [Language]
    let countries: [CountryGeometry]
    let regions: [RegionGeometry]
    let languagesByCode: [String: Language]

    static let shared = DataStore()

    private init() {
        territories = Self.load("territories.json", TerritoryFile.self).territories
        languages   = Self.load("languages.json",   LanguageFile.self).languages
        countries   = Self.load("geometry.json",    GeometryFile.self).countries
        regions     = Self.load("regions.json",     RegionFile.self).regions
        languagesByCode = Dictionary(uniqueKeysWithValues: languages.map { ($0.code, $0) })
    }

    /// Test-only constructor: bypasses the bundle and builds a store from in-memory data.
    init(territories: [String: Territory], languages: [Language], countries: [CountryGeometry],
        regions: [RegionGeometry] = []) {
        self.territories = territories
        self.languages = languages
        self.countries = countries
        self.regions = regions
        self.languagesByCode = Dictionary(uniqueKeysWithValues: languages.map { ($0.code, $0) })
    }

    private static func load<T: Decodable>(_ file: String, _ type: T.Type) -> T {
        guard let url = Bundle.main.url(forResource: file, withExtension: nil) else {
            fatalError("""
            Missing bundled resource \(file).
            Run: python3 scripts/build_data.py
            Then confirm the file is inside languageDLC/Resources/.
            """)
        }
        do { return try JSONDecoder().decode(T.self, from: Data(contentsOf: url)) }
        catch { fatalError("Failed to decode \(file): \(error)") }
    }

    private struct TerritoryFile: Decodable { let territories: [String: Territory] }
    private struct LanguageFile:  Decodable { let languages: [Language] }
    private struct GeometryFile:  Decodable { let countries: [CountryGeometry] }
    private struct RegionFile:    Decodable { let regions: [RegionGeometry] }
}
