# Language DLC — Implementation Plan

An iOS app where you pick languages and an interactive 3D globe lights up the parts of the
world you have "unlocked." Country color intensity = share of that country's population that
speaks your selected language(s).

---

## 0. How to use this document

**You are the implementing agent. Follow these rules literally.**

1. Work through the phases **in order**. Do not start Phase N+1 until every box in
   "Done when" for Phase N is checked.
2. Each phase lists **exact file paths** to create. Create them exactly there.
3. After each phase, run the build command in §0.3 and fix all errors before continuing.
4. **Never hand-edit `languageDLC.xcodeproj/project.pbxproj`.** This project uses Xcode
   synchronized file groups: any `.swift` or resource file placed inside the `languageDLC/`
   folder is added to the app target automatically. Just write files to disk.
5. If a step's assumption turns out false (a URL 404s, a UV orientation is flipped), the phase
   text tells you what to do. Do not invent a different architecture.
6. Commit after each phase with the message `Phase N: <short description>`.

### 0.1 Vocabulary

| Term | Meaning |
|---|---|
| **territory** | An ISO 3166-1 alpha-2 code like `MX`, `FR`, `NG`. Used as the primary key everywhere. |
| **coverage** | For one country and the user's selected languages: fraction 0.0–1.0 of that country's population that speaks at least one of them. |
| **equirectangular** | Flat map projection where x is a straight linear function of longitude and y of latitude. The only projection used in this app. |
| **texture map** | The 4096×2048 image drawn from country shapes and wrapped onto the 3D sphere. |
| **pick map** | A second, invisible image where every country is filled with a unique flat color encoding its index. Used to answer "which country did the user tap?" |
| **DLC** | The app's theme: unlocked regions are bright and saturated, locked regions are dim grey. |

### 0.2 Final architecture (read this once, then refer back)

```
                Python (build time, run once)
  Natural Earth GeoJSON ─┐
  Unicode CLDR XML ──────┴──> scripts/build_data.py ──> languageDLC/Resources/*.json
                                                                    │
                Swift (runtime)                                     │
                                                                    ▼
   GeoStore ─────────────┐                            LanguageStore  (loads JSON)
   (country outlines)    │                                  │
        │                │                                  ▼
        │                │                            AppState  (which languages are selected)
        ▼                │                                  │
   MapRasterizer ◄───────┴──────── CoverageEngine ◄──────────┘
   (draws CGImage)                 (pure math: coverage per territory)
        │        │
        │        └────────> pick map (CPU pixel buffer, never displayed)
        ▼                                    │
   GlobeView (SceneKit sphere)  ◄────tap─────┘
        │
        ▼
   ContentView  (globe + language picker sheet + stats HUD)
```

Two things make this tractable:

- **All drawing is 2D.** The globe is a plain sphere with a picture on it. You never write 3D
  geometry code for country borders.
- **Hit testing is a color lookup.** SceneKit gives you the texture coordinate of a tap; you
  read that pixel out of the pick map buffer and get a country index. No point-in-polygon math.

### 0.3 Build & test commands

Find the scheme and a simulator first (do this once, note the results):

```bash
cd /Users/tillmandean/Code/languageDLC
xcodebuild -list -project languageDLC.xcodeproj
xcrun simctl list devices available | grep iPhone | head -5
```

Then use these throughout (substitute the simulator name you found):

```bash
# Build
xcodebuild -project languageDLC.xcodeproj -scheme languageDLC \
  -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -30

# Unit tests
xcodebuild -project languageDLC.xcodeproj -scheme languageDLC \
  -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | tail -40
```

A phase is not done until the build command prints `** BUILD SUCCEEDED **`.

### 0.4 Known environment facts (already verified — do not re-check)

- Xcode 26.5, Swift 5 language mode, `objectVersion = 77` (synchronized groups).
- Deployment target is currently **iOS 26.5**. Phase 0 lowers it to 18.0.
- `python3` is 3.9.6, system Python. **Use only the standard library** in the data pipeline
  (`json`, `urllib.request`, `xml.etree.ElementTree`, `math`, `argparse`). Do not `pip install`.
- Existing files: `languageDLC/languageDLCApp.swift`, `languageDLC/ContentView.swift` (both
  still the template), plus empty test targets.
- Both data-source URLs in §1.1 were fetched successfully on 2026-09-10 (CLDR XML ≈ 395 KB,
  1630 `languagePopulation` entries). The reference figures in §1.5 were computed from that
  exact file, so they are ground truth, not guesses.

---

### 0.5 Where things stand (updated 2026-09-11, end of Phase 6)

**Resume at Phase 7.** Phases 0–6 are implemented and committed (`532e714`, `be2add3`,
`55116fc`, `10d3765`, `2cfbb82`, `4ad2470`, and Phase 6's commit). Both commands in §0.3 pass on
the iPhone 17 simulator: the build prints `** BUILD SUCCEEDED **` and the full test suite — 26
unit tests plus 5 UI tests — is green. (A UI-test run occasionally fails to launch the xctrunner
with `FBSOpenApplicationServiceErrorDomain`, and `GlobeRenderingTests` occasionally reports a
slow frame on a loaded simulator; both are simulator flakes, not the app. Re-run.)

Phase 6 added `languageDLC/Views/CountryDetailSheet.swift` and its `FocusedTerritory` wrapper.
`AppState.focused` stayed a plain `String?` — `ContentView` bridges it to `.sheet(item:)` with a
local `Binding<FocusedTerritory?>` rather than changing `AppState`'s stored type, so the existing
`focusedTerritory` accessibility label and `MapInteractionUITests` keep working unmodified. The
temporary Spanish/French buttons are still in `ContentView`; Phase 7 replaces them with the real
language picker.

Facts established at runtime that Phases 6–9 depend on:

- **`GlobeProjection` is the identity.** `SCNSphere` unwraps to exactly the rasterizer's
  equirectangular projection, so `flipV`, `mirrorU` and `uOffset` are all no-ops. This is
  measured on every test run, not assumed — see §5.1.
- **Taps go through `GlobeView.textureCoordinate(in:at:)`**, which already applies
  `GlobeProjection.decode` and the seam-miss workaround below. Phase 9 replaces
  `allowsCameraControl` with custom gestures — keep routing taps through that one function.
- `GlobeView.makeScene()` builds the scene, sphere and camera in one place so the tests
  calibrate against the geometry the app actually ships. Keep it that way.
- `ContentView` still holds the temporary Spanish/French buttons and a tapped-country label
  (accessibility identifier `focusedTerritory`, which `MapInteractionUITests` queries). Phases
  6–8 replace these; keep or move the identifier if the UI test should keep passing.
- `AppState.focused` is a `String?`. Phase 6's `.sheet(item:)` needs an `Identifiable` wrapper.
- `MapRasterizer.renderCalibrationTexture()` and the DEBUG-only "Calibrate" button in
  `ContentView` are the §5.1 debug path. Harmless to keep, fine to drop once the HUD lands.

Files added in Phase 5: `languageDLC/Rendering/GlobeView.swift`,
`languageDLCTests/GlobeProjectionTests.swift` (calibration + a frame-cost check).
`languageDLCUITests/FlatMapUITests.swift` was renamed to `MapInteractionUITests.swift` and
gained an end-to-end globe-tap test.

---

## Phase 0 — Project prep

**Goal:** clean folder structure, sane deployment target, app builds.

### Steps

1. Create these directories:

```bash
mkdir -p languageDLC/Models languageDLC/Data languageDLC/Rendering languageDLC/Views languageDLC/Resources scripts docs
```

2. Lower the deployment target so the app runs on more devices. Do this **in Xcode's UI or via
   `sed` on the pbxproj for this one setting only**:

```bash
sed -i '' 's/IPHONEOS_DEPLOYMENT_TARGET = 26.5;/IPHONEOS_DEPLOYMENT_TARGET = 18.0;/g' \
  languageDLC.xcodeproj/project.pbxproj
```

3. Add `.gitignore` at the repo root:

```
.DS_Store
build/
DerivedData/
*.xcuserstate
xcuserdata/
scripts/.cache/
```

4. Leave `ContentView.swift` alone for now. It gets replaced in Phase 4.

### Done when
- [ ] `xcodebuild ... build` prints `** BUILD SUCCEEDED **`.
- [ ] `grep IPHONEOS_DEPLOYMENT_TARGET languageDLC.xcodeproj/project.pbxproj` shows only `18.0`.
- [ ] The six new directories exist.

---

## Phase 1 — Data pipeline

**Goal:** one Python script that downloads public data and emits three JSON files into
`languageDLC/Resources/`.

### 1.1 Sources

| What | URL | Format | License |
|---|---|---|---|
| Country outlines | `https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_50m_admin_0_countries.geojson` | GeoJSON | Public domain |
| Language % per country + population | `https://raw.githubusercontent.com/unicode-org/cldr/main/common/supplemental/supplementalData.xml` | XML | Unicode License |

**Verify both before writing code:**

```bash
mkdir -p scripts/.cache
curl -sL -o scripts/.cache/countries.geojson "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_50m_admin_0_countries.geojson"
curl -sL -o scripts/.cache/cldr.xml "https://raw.githubusercontent.com/unicode-org/cldr/main/common/supplemental/supplementalData.xml"
ls -la scripts/.cache/
```

Both files must be > 100 KB. If either is tiny or contains `404: Not Found`:
- For Natural Earth, try `ne_110m_admin_0_countries.geojson` (lower detail but same structure),
  or the mirror `https://raw.githubusercontent.com/martynafford/natural-earth-geojson/master/50m/cultural/ne_50m_admin_0_countries.json`.
- For CLDR, try the tagged path `https://raw.githubusercontent.com/unicode-org/cldr/release-46/common/supplemental/supplementalData.xml`.
- If both fail, **stop and report to the user.** Do not fabricate language data.

### 1.2 What CLDR gives you

`supplementalData.xml` contains a `<territoryInfo>` block shaped like this:

```xml
<territoryInfo>
  <territory type="MX" gdp="2873000000000" literacyPercent="93.5" population="130740000">
    <languagePopulation type="es" populationPercent="83" officialStatus="de_facto_official"/>
    <languagePopulation type="en" populationPercent="13"/>
    <languagePopulation type="yua" populationPercent="0.67"/>
  </territory>
  ...
</territoryInfo>
```

That is exactly the app's data model: percentage of a territory's population that speaks a
language, plus whether it's official. `officialStatus` values present in the current file (verified): `official`, `de_facto_official`,
`official_regional`. The spec also allows `official_minority`, which does not currently appear —
so **decode this field leniently**; an unrecognized value must not crash the app.
An absent attribute means spoken but not official — "unofficial / widely understood."

**Normalization rules (apply all of them):**
- `type` may carry a script or region subtag (`zh_Hans`, `pt_PT`). Keep only the part before the
  first `_`. If two entries collapse to the same base code in one territory, **sum** the
  percentages and clamp to 100.
- Keep the "strongest" `officialStatus` when collapsing (rank:
  `official` > `de_facto_official` > `official_regional` > `official_minority` > none).
  Emit the raw CLDR string; do not invent new status values.
- Drop territories whose `type` is not 2 ASCII letters (skips UN M.49 numeric regions).
- Drop `languagePopulation` entries with `populationPercent` < 0.5 — they add noise and file size.

### 1.3 Output contracts

Write these three files. **The Swift code in later phases depends on these shapes exactly.**

`languageDLC/Resources/territories.json`
```json
{
  "version": 1,
  "territories": {
    "MX": { "name": "Mexico", "population": 130740000 },
    "FR": { "name": "France",  "population": 68000000 }
  }
}
```

`languageDLC/Resources/languages.json`
```json
{
  "version": 1,
  "languages": [
    {
      "code": "es",
      "name": "Spanish",
      "speakers": 512000000,
      "territories": {
        "MX": { "pct": 83.0, "status": "de_facto_official" },
        "ES": { "pct": 99.0, "status": "official" }
      }
    }
  ]
}
```
- `speakers` = Σ over territories of `population * pct / 100`, rounded to an integer. Used only
  for sorting the picker list.
- `name` = English name. Get it from CLDR if convenient, otherwise emit the raw code — Swift
  will resolve display names at runtime via `Locale`.
- Sort the array by `speakers` descending.

`languageDLC/Resources/geometry.json`
```json
{
  "version": 1,
  "countries": [
    {
      "id": "MX",
      "name": "Mexico",
      "labelLon": -102.0,
      "labelLat": 23.9,
      "rings": [ [-97.14, 25.97, -97.53, 24.99, -97.7, 24.27], [ ... ] ]
    }
  ]
}
```
- `rings` is an array of rings; each ring is a **flat** array `[lon, lat, lon, lat, ...]`.
  Flat arrays (not nested pairs) keep the file ~40% smaller and parse faster.
- Flatten every polygon of a `MultiPolygon` and every hole into this single list. Holes work
  automatically because the renderer fills with the even-odd rule.
- Round every coordinate to **2 decimal places** and drop a point if it is identical to the
  previous point after rounding. (One texture pixel ≈ 0.088°, so 0.01° is already 8× finer
  than needed.)
- Drop rings with fewer than 4 points after rounding.
- `id`: read GeoJSON property `ISO_A2_EH`, falling back to `ISO_A2`, then `WB_A2`. Skip features
  where the result is missing or `-99`.
- `labelLon`/`labelLat`: GeoJSON properties `LABEL_X`/`LABEL_Y`. If absent, use the centroid of
  the largest ring's bounding box.
- `name`: property `NAME` or `ADMIN`.

### 1.4 Script skeleton

Create `scripts/build_data.py`. This skeleton is deliberately incomplete in the marked spots —
fill them in following §1.2/§1.3.

```python
#!/usr/bin/env python3
"""Builds languageDLC/Resources/*.json from Natural Earth + Unicode CLDR."""
import json, os, urllib.request, xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CACHE = os.path.join(HERE, ".cache")
OUT = os.path.join(ROOT, "languageDLC", "Resources")

GEO_URL = "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_50m_admin_0_countries.geojson"
CLDR_URL = "https://raw.githubusercontent.com/unicode-org/cldr/main/common/supplemental/supplementalData.xml"

STATUS_RANK = {"official": 4, "de_facto_official": 3,
               "official_regional": 2, "official_minority": 1}


def fetch(url, name):
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, name)
    if not os.path.exists(path) or os.path.getsize(path) < 100_000:
        print("downloading", name)
        urllib.request.urlretrieve(url, path)
    size = os.path.getsize(path)
    if size < 100_000:
        raise SystemExit("download failed for %s (%d bytes)" % (name, size))
    return path


def build_language_data(cldr_path):
    root = ET.parse(cldr_path).getroot()
    territories = {}   # "MX" -> {"population": int}
    langs = {}         # "es" -> {"MX": {"pct": float, "status": str|None}}
    for terr in root.iter("territory"):
        code = terr.get("type", "")
        if len(code) != 2 or not code.isalpha():
            continue
        pop = int(float(terr.get("population", 0)))
        if pop <= 0:
            continue
        territories[code] = {"population": pop}
        for lp in terr.findall("languagePopulation"):
            # TODO: normalize the language code, clamp/sum percentages,
            #       keep the strongest officialStatus, drop pct < 0.5.
            pass
    return territories, langs


def build_geometry(geo_path):
    data = json.load(open(geo_path))
    out = []
    for feat in data["features"]:
        props = feat["properties"]
        # TODO: resolve id/name/label, flatten geometry into rings, round to 2dp.
        pass
    return out


def main():
    geo_path = fetch(GEO_URL, "countries.geojson")
    cldr_path = fetch(CLDR_URL, "cldr.xml")
    territories, langs = build_language_data(cldr_path)
    countries = build_geometry(geo_path)

    # Attach country names from Natural Earth to the territory table so the two agree.
    for c in countries:
        if c["id"] in territories:
            territories[c["id"]]["name"] = c["name"]
    territories = {k: v for k, v in territories.items() if "name" in v}

    os.makedirs(OUT, exist_ok=True)
    write(os.path.join(OUT, "territories.json"),
          {"version": 1, "territories": territories})
    write(os.path.join(OUT, "languages.json"),
          {"version": 1, "languages": assemble_languages(langs, territories)})
    write(os.path.join(OUT, "geometry.json"),
          {"version": 1, "countries": countries})
    report(territories, langs, countries)


def write(path, obj):
    with open(path, "w") as f:
        json.dump(obj, f, separators=(",", ":"))
    print("wrote %s (%.1f MB)" % (path, os.path.getsize(path) / 1e6))


if __name__ == "__main__":
    main()
```

### 1.5 Self-check the output

Add a `report()` function that prints, and eyeball the numbers:

These are **measured from the real data**, not estimates. Your output should match closely; if
it does not, your parsing is wrong. Fix it before moving on.

```
territories:            257           world population sum:  8.06B
languages:              ~479          countries with geometry: 240+
es -> 36 territories,   512M speakers   (6.4% of world)
en -> 149 territories, 1733M speakers  (21.5% of world)
zh -> 18 territories,  1324M speakers  (16.4% of world)
fr -> 64 territories,   333M speakers   (4.1% of world)
pt -> 14 territories,   249M speakers   (3.1% of world)

spot checks:  es in ES = 99    pt in BR = 91    en in NG = 53
              hi in IN = 41    fr in CA = 29    es in MX = 83
```

Note that ~50 CLDR territories are small dependencies with no distinct Natural Earth polygon;
losing under 20 of them to the geometry join is expected and fine.

### Done when
- [ ] `python3 scripts/build_data.py` completes with no traceback.
- [ ] All three JSON files exist under `languageDLC/Resources/` and are non-trivial in size
      (geometry ~1–3 MB, languages ~200–600 KB, territories < 50 KB).
- [ ] The report numbers land in the ranges above.
- [ ] Committed. Commit the generated JSON — the app ships fully offline.

---

## Phase 2 — Swift models and stores

**Goal:** load the three JSON files at launch into typed Swift values.

### Files

`languageDLC/Models/Models.swift`
```swift
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
}

struct CountryGeometry: Codable, Identifiable {
    let id: String
    let name: String
    let labelLon: Double
    let labelLat: Double
    let rings: [[Double]]        // flat [lon, lat, lon, lat, ...]
}
```

`languageDLC/Data/DataStore.swift`
```swift
import Foundation

/// Everything loaded from the bundle. Built once, then read-only.
final class DataStore {
    let territories: [String: Territory]
    let languages: [Language]
    let countries: [CountryGeometry]
    let languagesByCode: [String: Language]

    static let shared = DataStore()

    private init() {
        territories = Self.load("territories.json", TerritoryFile.self).territories
        languages   = Self.load("languages.json",   LanguageFile.self).languages
        countries   = Self.load("geometry.json",    GeometryFile.self).countries
        languagesByCode = Dictionary(uniqueKeysWithValues: languages.map { ($0.code, $0) })
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
}
```

> **If `fatalError("Missing bundled resource…")` fires:** the synchronized group did not pick
> up the JSON. Open `languageDLC.xcodeproj` in Xcode, drag the `Resources` folder onto the
> `languageDLC` group, check "Copy items if needed" and the `languageDLC` target, then rebuild.

### Test

`languageDLCTests/DataStoreTests.swift` — assert: ≥240 territories; ≥400 languages; ≥200
countries; `languagesByCode["es"]` exists and covers ≥30 territories, `["en"]` ≥120; every territory key
referenced by the top 20 languages that also exists in geometry has a non-zero population.

### Done when
- [ ] Build succeeds and the data tests pass.
- [ ] Loading time logged with `CFAbsoluteTimeGetCurrent()` is under 500 ms in the simulator.

---

## Phase 3 — Coverage engine (pure math, no UI)

**Goal:** given selected language codes, compute each country's coverage and the global stats.
This is pure, testable, and has no dependency on rendering.

`languageDLC/Data/CoverageEngine.swift`
```swift
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
```

### Test

`languageDLCTests/CoverageEngineTests.swift`:
- Empty selection → empty dictionary, stats all zero.
- Single language `["es"]` → `MX` coverage ≥ 0.9, `JP` absent or near 0.
- Union math: build a synthetic store where language A is 60% and B is 50% in one territory;
  assert coverage == 0.8 within 1e-9.
- `["en"]` alone should reach **21–22%** of world population (1.73B of 8.06B). Anything over
  30% means the pipeline is double-counting script subtags; anything under 15% means the
  0.5% filter is too aggressive.
- `["en", "zh", "es"]` should land near 42–46%. Because these barely overlap, the union formula
  is close to a plain sum here — a useful sanity check that the union math is not deflating.

### Done when
- [ ] All coverage tests pass.
- [ ] No UI code has been written yet. (If you were tempted, re-read §0 rule 1.)

---

## Phase 4 — Rasterizer and flat-map milestone

**Goal (Milestone A):** show a flat colored world map in SwiftUI. This validates geometry,
projection, and coloring before any 3D work.

### 4.1 Projection

Both maps are equirectangular with the image's top-left at (180°W, 90°N):

```
x = (lon + 180) / 360 * width
y = (90 - lat)  / 180 * height
```

### 4.2 Antimeridian handling — do not skip this

Russia, Fiji and New Zealand have rings whose points straddle ±180°. Drawn naively they slash a
horizontal band across the whole map. Fix with **unwrap + three copies**:

1. Walking a ring, keep a running longitude. For each point after the first, while
   `lon - previous > 180` subtract 360; while `lon - previous < -180` add 360. Points may now
   exceed ±180 — that is intended.
2. Build the path from the unwrapped points, then **stroke/fill it three times**, at pixel
   x-offsets of `-width`, `0`, and `+width`. Core Graphics clips whatever falls off canvas.

### 4.3 Files

`languageDLC/Rendering/MapRasterizer.swift`

Responsibilities:

```swift
final class MapRasterizer {
    let width: Int, height: Int
    private(set) var ids: [String] = []            // index -> territory code
    private var paths: [CGPath] = []               // parallel to ids, in pixel space
    private var pickBuffer: [UInt8] = []           // RGBA, width*height*4

    init(countries: [CountryGeometry], width: Int = 4096, height: Int = 2048)

    /// Draws the visible globe texture.
    func renderTexture(colors: [String: CGColor],
                       ocean: CGColor,
                       lockedLand: CGColor,
                       borders: CGColor) -> CGImage

    /// Draws the invisible index map. Call once in init; result cached in pickBuffer.
    private func renderPickMap()

    /// u, v in 0...1 (texture coordinates). Returns nil for ocean.
    func territory(atU u: Double, v: Double, tolerancePixels: Int = 12) -> String?
}
```

Implementation notes, in order of how easy they are to get wrong:

- **Build `paths` once in `init`**, in pixel space, applying §4.2. Re-coloring later is then
  just "fill N cached paths," which takes ~10–20 ms instead of re-parsing coordinates.
- Create contexts with a **top-left origin** so the projection formula above works directly:

```swift
let ctx = CGContext(data: nil, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.translateBy(x: 0, y: CGFloat(height))
ctx.scaleBy(x: 1, y: -1)
```

- Fill with `.evenOdd` so holes (San Marino in Italy, Lesotho-shaped enclaves) come out right.
- **Pick map must have antialiasing off:** `ctx.setShouldAntialias(false)` and
  `ctx.interpolationQuality = .none`. A blended edge pixel decodes to a random country.
- Encode index into color as `r = (i+1) & 0xFF`, `g = ((i+1) >> 8) & 0xFF`, `b = 0`, `a = 255`.
  Index 0 is reserved for ocean. Decode with
  `let idx = Int(buf[o]) | (Int(buf[o+1]) << 8)`; `idx == 0` means ocean.
- Render the pick map at **2048×1024** (8 MB buffer) even though the texture is 4096×2048.
  Halving costs nothing in accuracy at tap resolution.
- Tiny countries (Singapore, Malta, Bahrain) vanish at this resolution. After filling a
  country's paths, if its bounding box is smaller than 3 px in either dimension, additionally
  fill a 3 px-radius circle at `labelLon/labelLat`. Do this in **both** maps so tapping works.
- `territory(atU:v:)` should, when it hits ocean, spiral outward up to `tolerancePixels` and
  return the first non-ocean index found. This makes small islands tappable.

`languageDLC/Rendering/Palette.swift`
```swift
import UIKit

enum Palette {
    /// Assigned to selected languages by selection order.
    static let languageHues: [CGFloat] = [0.55, 0.08, 0.33, 0.80, 0.14, 0.92, 0.47, 0.65]

    static let ocean      = UIColor(white: 0.06, alpha: 1).cgColor
    static let lockedLand = UIColor(white: 0.20, alpha: 1).cgColor
    static let borders    = UIColor(white: 0.32, alpha: 1).cgColor

    /// Coverage 0...1 -> a bright, saturated fill. Low coverage stays dim and desaturated,
    /// so "unlocked" reads instantly on the globe.
    static func fill(hue: CGFloat, coverage: Double) -> CGColor {
        let c = CGFloat(min(max(coverage, 0), 1))
        let saturation = 0.35 + 0.55 * c
        let brightness = 0.30 + 0.62 * c
        return UIColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1).cgColor
    }

    static func hue(forSelectionIndex i: Int) -> CGFloat {
        languageHues[i % languageHues.count]
    }
}
```

`languageDLC/Data/AppState.swift`
```swift
import Foundation
import Observation

@Observable
final class AppState {
    var selected: [String] = [] {          // ordered; order determines color
        didSet { persist(); recompute() }
    }
    private(set) var coverage: [String: CountryCoverage] = [:]
    private(set) var stats: WorldStats = WorldStats(peopleReached: 0, worldPopulation: 0,
                                                    countriesMajority: 0, countriesAny: 0,
                                                    countriesOfficial: 0)
    var focused: String?                    // tapped territory

    private let store = DataStore.shared
    private let key = "selectedLanguages"

    init() {
        selected = (UserDefaults.standard.array(forKey: key) as? [String]) ?? []
        recompute()
    }

    func toggle(_ code: String) {
        if let i = selected.firstIndex(of: code) { selected.remove(at: i) }
        else { selected.append(code) }
    }

    func hue(for code: String) -> CGFloat {
        Palette.hue(forSelectionIndex: selected.firstIndex(of: code) ?? 0)
    }

    /// territory -> fill color, ready for the rasterizer.
    func fillColors() -> [String: CGColor] {
        coverage.compactMapValues { c in
            guard let dom = c.dominantLanguage else { return nil }
            return Palette.fill(hue: hue(for: dom), coverage: c.coverage)
        }
    }

    private func recompute() {
        coverage = CoverageEngine.coverage(for: selected, in: store)
        stats = CoverageEngine.stats(coverage, in: store)
    }
    private func persist() { UserDefaults.standard.set(selected, forKey: key) }
}
```

### 4.4 Milestone A view

Replace `ContentView.swift` with a temporary flat-map screen: an `Image(uiImage:)` of
`renderTexture(...)` sized `.scaledToFit()`, plus two hard-coded buttons that toggle `"es"` and
`"fr"` on `AppState`.

Do the render on a background task and hand the `CGImage` back on the main actor:

```swift
.task(id: state.selected) {
    let colors = state.fillColors()
    let image = await Task.detached(priority: .userInitiated) {
        rasterizer.renderTexture(colors: colors, ocean: Palette.ocean,
                                 lockedLand: Palette.lockedLand, borders: Palette.borders)
    }.value
    self.texture = image
}
```

### Done when
- [ ] The simulator shows a recognizable world map with correct continent shapes.
- [ ] Antarctica is a band along the bottom; Greenland is at the top-left of Europe; nothing
      slashes horizontally across the Pacific.
- [ ] Tapping "Spanish" lights up Spain, Mexico, and South America minus Brazil.
- [ ] Toggling a language re-renders in under ~250 ms and the UI never freezes.

**Do not proceed until the flat map is correct.** Every 3D bug after this point is much harder
to diagnose if the 2D map is wrong.

---

## Phase 5 — The globe (Milestone B)

**Goal:** the same texture, wrapped on a rotatable sphere.

> **Note on SceneKit:** Apple now steers new work toward RealityKit, and you may see
> deprecation warnings. SceneKit still ships and works, and it is by far the shortest path to a
> textured sphere. Use it. Appendix B has the RealityKit equivalent if you are ever forced off it.

`languageDLC/Rendering/GlobeView.swift`
```swift
import SwiftUI
import SceneKit

struct GlobeView: UIViewRepresentable {
    var texture: CGImage?
    var onTap: (CGPoint) -> Void      // reports texture coordinates (u, v), each 0...1

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        let scene = SCNScene()
        view.scene = scene
        view.backgroundColor = .black
        view.antialiasingMode = .multisampling2X
        view.allowsCameraControl = true          // replaced with custom gestures in Phase 9
        view.autoenablesDefaultLighting = false

        let sphere = SCNSphere(radius: 1)
        sphere.segmentCount = 96                 // 96 avoids visible faceting at the silhouette
        let material = sphere.firstMaterial!
        material.lightingModel = .constant       // texture colors render exactly as drawn
        material.diffuse.wrapS = .repeat
        material.diffuse.mipFilter = .linear
        material.isDoubleSided = false

        let node = SCNNode(geometry: sphere)
        node.name = "globe"
        scene.rootNode.addChildNode(node)

        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 45
        camera.position = SCNVector3(0, 0, 3)
        scene.rootNode.addChildNode(camera)
        view.pointOfView = camera

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)
        context.coordinator.view = view
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.onTap = onTap
        if let texture {
            view.scene?.rootNode.childNode(withName: "globe", recursively: false)?
                .geometry?.firstMaterial?.diffuse.contents = texture
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onTap: onTap) }

    final class Coordinator: NSObject {
        weak var view: SCNView?
        var onTap: (CGPoint) -> Void
        init(onTap: @escaping (CGPoint) -> Void) { self.onTap = onTap }

        @objc func handleTap(_ g: UITapGestureRecognizer) {
            guard let view else { return }
            let p = g.location(in: view)
            guard let hit = view.hitTest(p, options: [.searchMode: SCNHitTestSearchMode.closest.rawValue]).first
            else { return }
            onTap(hit.textureCoordinates(withMappingChannel: 0))
        }
    }
}
```

### 5.1 UV calibration — expect to do this, it is not a bug

`SCNSphere`'s texture wrapping orientation (where u=0 sits, and whether v runs top-down) is not
worth guessing at. Calibrate empirically, once:

1. Add a debug flag to `MapRasterizer` that draws a calibration texture instead of the map:
   a red 40 px dot at (0° lat, 0° lon), a green dot at (0°, 90°E), a blue dot at (0°, 90°W),
   and a white bar across the top 20 rows.
2. Run it. Rotate the globe.
3. Check: the white bar must be at the **north pole**. If it is at the south pole, `v` is
   flipped.
4. Check: with the red dot facing you, the green dot must be to the **right** as the globe
   rotates eastward. If left, `u` is mirrored.
5. Encode the answer in one place and use it in **both** directions (drawing and tap decoding):

```swift
struct GlobeProjection {
    static var flipV = false     // set from step 3
    static var mirrorU = false   // set from step 4
    static var uOffset = 0.0     // fine longitude shift, 0...1, from step 4

    static func decode(_ tc: CGPoint) -> (u: Double, v: Double) {
        var u = Double(tc.x) - uOffset
        if mirrorU { u = 1 - u }
        u = u - floor(u)                       // wrap into 0...1
        let v = flipV ? 1 - Double(tc.y) : Double(tc.y)
        return (u, min(max(v, 0), 1))
    }
}
```

6. Verify by printing `territory(atU:v:)` for taps on five known places: Brazil, Australia,
   Japan, Egypt, Alaska. All five must be right before you move on.

**Result (2026-09-10): all three corrections are no-ops.** `SCNSphere` carries texture
coordinates identical to the rasterizer's projection — v = 0 at the north pole, u = 0 at 180°W
rising eastward, seam at the back — so `flipV = false`, `mirrorU = false`, `uOffset = 0`.

It is checked rather than trusted. `GlobeProjectionTests` reads the sphere's own UV geometry
source and compares every vertex against the rasterizer's formula, renders a two-tone probe
texture offscreen to prove the image's top lands on the north pole, hit-tests left/right and
up/down for orientation, and runs the five named places of step 6 through the real path
(sphere UV → screen point → SceneKit hit test → `decode` → pick map). If SceneKit ever changes
its unwrapping, those tests fail instead of the map quietly going crooked.

Two things the steps above do not warn about, both fixed in `GlobeView.swift`:

- **SceneKit reports a miss for a ray landing exactly on a shared triangle edge**, and the
  sphere's seam column runs straight down the middle of the view — so every tap on the exact
  centre line did nothing. `textureCoordinate(in:at:)` retries half a point to the side.
- **A 45° field of view is measured vertically by default**, which makes the globe wider than a
  portrait phone (it was cut off at both edges). `camera.projectionDirection = .horizontal`
  fits the sphere at any aspect ratio.

Two notes on testing SceneKit offscreen, if you write more of these: hit testing reads
*presentation* values, so a node's new transform does not take effect until something renders
(`_ = view.snapshot()` is enough), and the suite is marked `.serialized` because concurrent
`SCNView`s are unreliable.

### 5.2 Presentation

- `scene.background.contents` = a dark gradient or star field `UIImage`. Black is fine for now.
- Idle auto-rotation on the globe node, cancelled on first user touch:
  `node.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 90)))`.

### Done when
- [x] A rotatable sphere shows the world map; continents are recognizable from every angle.
      Verified in the simulator: screenshots 8 s apart show the Atlantic view rotating to the
      Americas, with east to the right.
- [x] Toggling a language updates the sphere's texture without stutter.
      (`MapInteractionUITests.testTogglingLanguageUpdatesTheMap`.)
- [x] The five calibration taps in §5.1 step 6 all return the correct country.
- [x] Frame rate stays at 60 fps while dragging — **measured differently.** The statistics
      overlay would not surface in a simulator screenshot, so `GlobeRenderingTests` renders 30
      textured frames offscreen and asserts each costs well under 16.6 ms. It passes with room
      to spare, but that is a simulator number; confirm on a device when one is at hand.

---

## Phase 6 — Tap to inspect a country

**Goal:** tapping a country opens a detail sheet.

1. `ContentView` holds the `MapRasterizer` and passes
   `onTap: { tc in let (u, v) = GlobeProjection.decode(tc); state.focused = rasterizer.territory(atU: u, v: v) }`.
2. `languageDLC/Views/CountryDetailSheet.swift`, presented with
   `.sheet(item: $state.focused)` (wrap the `String` in a small `Identifiable` struct):
   - Country name, flag emoji (derive from the ISO code by offsetting each letter into the
     regional-indicator range, `0x1F1E6 + (ascii - 65)`), population.
   - Big "Unlocked: 74%" figure with a progress bar tinted by the dominant language's hue.
   - A list of **all** languages spoken there over 1%, each row: display name, percentage bar,
     `officialStatus` label, and a plus/checkmark button to add or remove it from the selection.
     This is the app's discovery loop — tap a country, see what would unlock it, add the language.
   - Sort selected languages to the top.
3. Haptic `UIImpactFeedbackGenerator(style: .light)` on a successful tap; nothing on ocean.

### Done when
- [ ] Tapping any country opens the sheet with correct data.
- [ ] Tapping the ocean does nothing (no empty sheet).
- [ ] Adding a language from the sheet immediately recolors the globe behind it.

---

## Phase 7 — Language picker

`languageDLC/Views/LanguagePickerSheet.swift`

- `.searchable` list over `DataStore.shared.languages`, already sorted by speaker count.
- Filter out languages with `speakers < 1_000_000` behind a "Show rare languages" toggle,
  otherwise the list is 300+ entries of noise.
- Each row: colored dot (the language's assigned hue if selected, grey otherwise), display name,
  native name if different, "N countries · 493M speakers", and a checkmark.
- A pinned "Selected" section at the top so users can deselect without scrolling.
- Cap the selection at 8 languages (the palette length) with a gentle alert past that.
- Sheet detents `[.medium, .large]` so the globe stays visible while picking.

### Done when
- [ ] Search for "port" finds Portuguese; "arab" finds Arabic.
- [ ] Selecting/deselecting updates the globe live behind a `.medium` detent sheet.
- [ ] Selection survives an app relaunch (UserDefaults).

---

## Phase 8 — The "DLC" HUD

This is the part that makes the app feel like the pitch rather than a data viewer.

`languageDLC/Views/StatsHUD.swift`, overlaid at the top of the globe:

- **"World unlocked: 31.4%"** — big, animated with `.contentTransition(.numericText())`.
- A thin progress bar under it, gradient-filled with the hues of the selected languages.
- Secondary row: "1.4B people · 47 countries · official in 21".
- A row of dismissible chips, one per selected language, in its color, tap to remove.
- Empty state (nothing selected): a centered card — "Pick a language to see what you unlock."

Suggested numeric animation: wrap `state.stats` updates in
`withAnimation(.snappy(duration: 0.35))`.

Nice-to-have if time allows: when a newly selected language pushes world coverage past a
threshold (10/25/50/75%), show a brief "achievement" toast. That is the DLC metaphor paying off.

### Done when
- [ ] Percentages animate rather than snapping.
- [ ] The empty state appears on a fresh install.
- [ ] The HUD does not block globe rotation gestures (use `.allowsHitTesting(false)` on
      non-interactive parts).

---

## Phase 9 — Polish and correctness

1. **Custom globe gestures.** Replace `allowsCameraControl = true` with:
   - `DragGesture` → rotate the globe node around Y by `dx * 0.005`, around X by `dy * 0.005`,
     **clamped to ±80°** on X so the globe never flips upside down.
   - `MagnificationGesture` → move the camera's z between 1.6 and 6.
   - Momentum: on drag end, apply a decaying rotation over ~0.8 s.
2. **Accessibility.** VoiceOver cannot use a sphere. Add a "List" mode toggle: a plain
   `List` of countries sorted by coverage, with the same detail sheet. Give the globe an
   `.accessibilityLabel` describing the current stats.
3. **Dark/light.** The app is dark-only by design; set `.preferredColorScheme(.dark)`.
4. **Data caveat.** Add an info button → a short sheet: figures come from the Unicode CLDR
   territory-language dataset, are approximate, include second-language speakers, and country
   outlines come from Natural Earth. Credit both licenses. Ship this — the numbers will be
   argued with, and being upfront is the correct answer.
5. **Memory.** The 4096×2048 texture is 32 MB. Hold exactly one at a time; drop the previous
   `CGImage` before assigning the new one. If you see memory warnings on older devices, drop the
   texture to 2048×1024 — set it in one constant.
6. **Launch time.** If `DataStore` init exceeds 500 ms, move geometry parsing off the main
   thread behind a loading state.

### Done when
- [ ] Globe cannot be rotated past the poles.
- [ ] List mode is fully usable with VoiceOver on.
- [ ] Memory in Instruments stays under 200 MB while toggling languages repeatedly.
- [ ] Attribution sheet exists.

---

## Phase 10 — Stretch goals (only after 0–9 are done)

Ranked by value per unit of work:

1. **Sub-national regions.** Add Natural Earth `ne_50m_admin_1_states_provinces` for a curated
   list (US states, Canadian provinces, Spanish autonomous communities, Indian states,
   Swiss cantons, Belgian regions). Extend `overrides.json` with region-level percentages, keyed
   `"US-TX"`. The rasterizer already handles arbitrary polygon IDs — draw these on top of the
   country fill.
2. **`overrides.json`.** A hand-curated file, merged after CLDR in the pipeline, for known gaps
   (English comprehension in the Nordics, Russian in Central Asia). Same shape as a language's
   `territories` map. Keeps corrections out of the generated files.
3. **Learning goals.** "If you learn Portuguese next, you gain +3.1% world coverage" — compute
   marginal gain for every unlearned language against the current selection and rank them. This
   is a genuinely fun feature and is a ~40-line addition to `CoverageEngine`.
4. **Share card.** Render the globe to a `UIImage` plus the stats line, share sheet out.
5. **Widget.** Home screen widget showing current world coverage.
6. **iPad / visionOS.** The SceneKit view already adapts; mainly a layout job.

---

## Appendix A — Pitfall checklist

| Symptom | Cause | Fix |
|---|---|---|
| Horizontal slash across the Pacific | Antimeridian not unwrapped | §4.2 |
| Map upside down | Missing the flip transform on the CGContext | §4.3 |
| Taps return wrong/neighboring countries | Antialiasing on in the pick map | `setShouldAntialias(false)` |
| Taps are consistently offset by a fixed amount | UV offset uncalibrated | §5.1 |
| Small countries untappable | No minimum-radius dot | §4.3 |
| `fatalError` on missing resource | JSON not in the bundle | §Phase 2 note |
| Coverage > 100% | Summing percentages instead of union | §Phase 3 |
| English shows >30% of the world | CLDR script-subtag duplicates summed twice | §1.2 |
| Toggling a language freezes the UI | Rasterizing on the main thread | §4.4 |
| Faceted globe silhouette | `segmentCount` too low | Set to 96 |
| Taps on the vertical centre line of the view do nothing | Ray landing exactly on the sphere's seam edge reads as a miss | Retry half a point to the side, §5.1 |
| Globe is cut off at the left and right edges | `fieldOfView` is measured vertically by default | `camera.projectionDirection = .horizontal`, §5.1 |
| A node's new transform does not affect hit testing | Hit tests read presentation values, which only a render syncs | Force a frame (`_ = view.snapshot()`) first |

## Appendix B — RealityKit fallback

If SceneKit becomes unusable, the swap is contained to `GlobeView.swift`:

```swift
let mesh = MeshResource.generateSphere(radius: 1)
var material = UnlitMaterial()
material.color = .init(texture: .init(try TextureResource(image: cgImage, options: .init(semantic: .color))))
let entity = ModelEntity(mesh: mesh, materials: [material])
entity.generateCollisionShapes(recursive: false)
```

Hit testing: `arView.hitTest(point)` gives a world-space position; convert it to the entity's
local frame, normalize, then derive lat/lon directly —
`lat = asin(p.y) * 180/π`, `lon = atan2(p.x, p.z) * 180/π` — and turn that into (u, v) with the
Phase 4 projection. This path skips `textureCoordinates` entirely, so §5.1's calibration
reduces to checking the sign of `lon`.

## Appendix C — File manifest

```
scripts/build_data.py                        Phase 1
languageDLC/Resources/territories.json       Phase 1 (generated)
languageDLC/Resources/languages.json         Phase 1 (generated)
languageDLC/Resources/geometry.json          Phase 1 (generated)
languageDLC/Models/Models.swift              Phase 2
languageDLC/Data/DataStore.swift             Phase 2
languageDLC/Data/CoverageEngine.swift        Phase 3
languageDLC/Data/AppState.swift              Phase 4
languageDLC/Rendering/MapRasterizer.swift    Phase 4
languageDLC/Rendering/Palette.swift          Phase 4
languageDLC/Rendering/GlobeView.swift        Phase 5
languageDLC/Views/CountryDetailSheet.swift   Phase 6
languageDLC/Views/LanguagePickerSheet.swift  Phase 7
languageDLC/Views/StatsHUD.swift             Phase 8
languageDLC/ContentView.swift                Phase 4 (flat), rewritten Phase 5
languageDLCTests/DataStoreTests.swift        Phase 2
languageDLCTests/CoverageEngineTests.swift   Phase 3
```
