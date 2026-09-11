import Foundation

struct Territory: Codable, Hashable {
    let name: String
    let population: Int
}

enum OfficialStatus: String, Codable {
    case official
    case deFactoOfficial  = "de_facto_official"
    case officialRegional = "official_regional"
    case officialMinority = "official_minority"
    case other                                    // catch-all: never crash on new CLDR values

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = OfficialStatus(rawValue: raw) ?? .other
    }

    var label: String {
        switch self {
        case .official, .deFactoOfficial: return "Official"
        case .officialRegional:           return "Officially regional"
        case .officialMinority:           return "Recognized minority"
        case .other:                      return "Recognized"
        }
    }
}

struct LanguagePresence: Codable, Hashable {
    let pct: Double              // 0...100
    let status: OfficialStatus?  // nil = spoken but not official
}

struct Language: Codable, Identifiable, Hashable {
    let code: String
    let name: String
    let speakers: Int
    let territories: [String: LanguagePresence]

    var id: String { code }

    /// Prefer the OS's localized name; fall back to the name baked into the JSON.
    var displayName: String {
        Locale.current.localizedString(forLanguageCode: code) ?? name
    }

    /// The language's own name for itself (e.g. "Español" for Spanish), if distinct from
    /// `displayName`. Best-effort: some codes (macrolanguages, script variants) resolve to
    /// nothing meaningful, so callers should treat `nil` as "don't show a second line."
    var nativeName: String? {
        Locale(identifier: code).localizedString(forLanguageCode: code)?.capitalized
    }
}

struct CountryGeometry: Codable, Identifiable {
    let id: String
    let name: String
    let labelLon: Double
    let labelLat: Double
    let rings: [[Double]]        // flat [lon, lat, lon, lat, ...]
}
