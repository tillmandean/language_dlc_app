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
    /// Territory entries only, and only where curated regions carve into this country: the
    /// percentage for the *rest* of it, once those regions are carved out. `pct` stays the
    /// whole-country figure and is what speaker counts and world coverage use; `restPct` exists
    /// so the map doesn't fill the remainder with an average that already includes the regions
    /// drawn on top of it. Derived in `scripts/build_data.py`; `nil` means "no curated regions
    /// here, `pct` is the whole story."
    var restPct: Double? = nil
}

struct Language: Codable, Identifiable, Hashable {
    let code: String
    let name: String
    let speakers: Int
    let territories: [String: LanguagePresence]
    /// Curated sub-national presence, keyed by ISO 3166-2 region id (e.g. "ES-CT"). Absent for
    /// almost every language — there is no authoritative sub-national source, so this only
    /// exists where PLAN.md Phase 10.4 hand-curated it. `nil` means "no curated regions," same
    /// convention as `nativeName`.
    var regions: [String: LanguagePresence]? = nil

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

/// What a tap on the globe resolved to.
///
/// Curated regions are drawn into the pick map on top of their country, so a tap inside one
/// resolves to the region and a tap anywhere else in that country still resolves to the country.
/// Only a minority of countries have curated regions at all, so both cases stay common.
enum MapFeature: Hashable, Identifiable {
    case country(String)                        // ISO 3166-1 alpha-2
    case region(id: String, country: String)    // ISO 3166-2, plus its alpha-2 prefix

    var id: String {
        switch self {
        case .country(let code):  return code
        case .region(let id, _):  return id
        }
    }

    /// The country this sits in, region or not — what territory population and whole-country
    /// coverage lookups key on.
    var territory: String {
        switch self {
        case .country(let code):     return code
        case .region(_, let country): return country
        }
    }
}

/// A curated sub-national region (e.g. a Swiss canton), drawn on top of its country's fill.
/// Phase 10.4 — see PLAN.md for the curated list and why it's province/canton/state-level.
struct RegionGeometry: Codable, Identifiable {
    let id: String                // ISO 3166-2, e.g. "ES-CT"
    let country: String           // the 2-letter prefix of `id`
    let name: String
    let labelLon: Double
    let labelLat: Double
    let rings: [[Double]]
    /// From Wikidata (P1082), scaled down where a country's curated regions sum past its CLDR
    /// population. Used at build time as the within-country weight for `LanguagePresence.restPct`.
    var population: Int = 0
}
