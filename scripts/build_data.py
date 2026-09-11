#!/usr/bin/env python3
"""Builds languageDLC/Resources/*.json from Natural Earth + Unicode CLDR.

Stdlib only (system python3 has no pip-installed packages available).
Run from anywhere: `python3 scripts/build_data.py`.
"""
import json
import os
import urllib.request
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CACHE = os.path.join(HERE, ".cache")
OUT = os.path.join(ROOT, "languageDLC", "Resources")
OVERRIDES_PATH = os.path.join(HERE, "overrides.json")

GEO_URL = "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_50m_admin_0_countries.geojson"
CLDR_URL = "https://raw.githubusercontent.com/unicode-org/cldr/main/common/supplemental/supplementalData.xml"
# Admin-1 (state/province) boundaries. The 50m export only carries a handful of large
# countries — Switzerland, Belgium and Spain are missing from it entirely — so this uses the
# 10m export instead, just for the curated subset of regions below.
ADMIN1_URL = "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_10m_admin_1_states_provinces.geojson"

# Curated sub-national regions with a genuinely distinct language story (Phase 10.4). Natural
# Earth models Belgium and Spain at the province level, not by linguistic region/autonomous
# community, so those two countries list every province in the relevant group (e.g. all five
# Catalan-speaking Spanish provinces) rather than one shape per region.
REGION_IDS = {
    # Switzerland: all 26 cantons.
    "CH-ZH", "CH-BE", "CH-LU", "CH-UR", "CH-SZ", "CH-OW", "CH-NW", "CH-GL", "CH-ZG", "CH-FR",
    "CH-SO", "CH-BS", "CH-BL", "CH-SH", "CH-AR", "CH-AI", "CH-SG", "CH-GR", "CH-AG", "CH-TG",
    "CH-TI", "CH-VD", "CH-VS", "CH-NE", "CH-GE", "CH-JU",
    # Belgium: every province, grouped by language in overrides.json.
    "BE-VWV", "BE-VOV", "BE-VAN", "BE-VLI", "BE-VBR", "BE-WHT", "BE-WNA", "BE-WLX", "BE-WLG",
    "BE-WBR", "BE-BRU",
    # Spain: provinces of the five autonomous communities with a co-official regional language.
    "ES-B", "ES-GI", "ES-L", "ES-T",              # Cataluña (Catalan)
    "ES-VI", "ES-BI", "ES-SS",                    # País Vasco (Basque)
    "ES-C", "ES-LU", "ES-OR", "ES-PO",             # Galicia (Galician)
    "ES-CS", "ES-V", "ES-A",                      # Valenciana (Catalan/Valencian)
    "ES-PM",                                      # Islas Baleares (Catalan)
    # Canada.
    "CA-QC", "CA-NB",
    # India: major regional-language states.
    "IN-TN", "IN-WB", "IN-PB", "IN-KL", "IN-MH", "IN-KA", "IN-GJ", "IN-OR", "IN-AS", "IN-TG",
    # United States: notable Spanish-at-home share.
    "US-TX", "US-CA", "US-NM", "US-AZ", "US-FL", "US-NV", "US-CO", "US-NY",
}

# Rank used both when collapsing duplicate script/region subtags for one
# language in one territory, and when picking the "best" status a selected
# language has anywhere. Unrecognized future CLDR values rank just above
# "no status" rather than crashing the build.
STATUS_RANK = {
    "official": 4,
    "de_facto_official": 3,
    "official_regional": 2,
    "official_minority": 1,
}


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
    """Returns (territories, langs).

    territories: "MX" -> {"population": int}
    langs:       "es" -> {"MX": {"pct": float, "status": str|None}, ...}
    """
    root = ET.parse(cldr_path).getroot()
    territories = {}
    langs = {}

    for terr in root.iter("territory"):
        code = terr.get("type", "")
        if len(code) != 2 or not code.isalpha():
            continue
        pop = int(float(terr.get("population", 0) or 0))
        if pop <= 0:
            continue
        territories[code] = {"population": pop}

        # Collapse script/region subtags (zh_Hans, pt_PT -> zh, pt) by summing
        # percentages (clamped to 100) and keeping the strongest status seen.
        agg = {}  # base_code -> {"pct": float, "status": str|None}
        for lp in terr.findall("languagePopulation"):
            raw_type = lp.get("type", "")
            if not raw_type:
                continue
            base = raw_type.split("_")[0]
            pct = float(lp.get("populationPercent", 0) or 0)
            if pct < 0.5:
                continue
            status = lp.get("officialStatus")  # None if absent

            entry = agg.get(base)
            if entry is None:
                agg[base] = {"pct": pct, "status": status}
            else:
                entry["pct"] = min(100.0, entry["pct"] + pct)
                if STATUS_RANK.get(status, 0) > STATUS_RANK.get(entry["status"], 0):
                    entry["status"] = status

        for base, entry in agg.items():
            langs.setdefault(base, {})[code] = entry

    return territories, langs


def _round_ring(points):
    """points: flat [lon, lat, lon, lat, ...]. Rounds to 2dp and drops
    consecutive duplicates."""
    out = []
    prev = None
    for i in range(0, len(points), 2):
        lon = round(points[i], 2)
        lat = round(points[i + 1], 2)
        if prev is not None and prev == (lon, lat):
            continue
        out.append(lon)
        out.append(lat)
        prev = (lon, lat)
    return out


def _flatten_rings(geometry):
    """Flattens a Polygon or MultiPolygon (all rings, including holes) into
    a list of flat [lon, lat, ...] rings, rounded and deduped."""
    gtype = geometry["type"]
    coords = geometry["coordinates"]
    if gtype == "Polygon":
        polygons = [coords]
    elif gtype == "MultiPolygon":
        polygons = coords
    else:
        return []

    rings = []
    for polygon in polygons:
        for ring in polygon:  # ring: [[lon,lat], [lon,lat], ...]
            flat = []
            for lon, lat in ring:
                flat.append(lon)
                flat.append(lat)
            rounded = _round_ring(flat)
            if len(rounded) >= 8:  # >= 4 points
                rings.append(rounded)
    return rings


def _bbox_centroid(rings):
    """Centroid of the bounding box of the largest ring (by point count),
    used as a label-position fallback when LABEL_X/LABEL_Y are absent."""
    if not rings:
        return 0.0, 0.0
    largest = max(rings, key=len)
    lons = largest[0::2]
    lats = largest[1::2]
    return (min(lons) + max(lons)) / 2.0, (min(lats) + max(lats)) / 2.0


def build_geometry(geo_path):
    data = json.load(open(geo_path))
    out = []
    seen_ids = set()
    for feat in data["features"]:
        props = feat["properties"]
        code = props.get("ISO_A2_EH") or props.get("ISO_A2") or props.get("WB_A2")
        if not code or code == "-99" or len(code) != 2:
            continue
        if code in seen_ids:
            continue  # keep first occurrence only (a handful of disputed territories repeat a code)

        rings = _flatten_rings(feat["geometry"])
        if not rings:
            continue

        name = props.get("NAME") or props.get("ADMIN") or code
        label_x = props.get("LABEL_X")
        label_y = props.get("LABEL_Y")
        if label_x is None or label_y is None:
            label_x, label_y = _bbox_centroid(rings)

        seen_ids.add(code)
        out.append({
            "id": code,
            "name": name,
            "labelLon": round(float(label_x), 2),
            "labelLat": round(float(label_y), 2),
            "rings": rings,
        })
    return out


def build_regions(geo_path):
    """Same shape as build_geometry's output plus a `country` field, filtered to REGION_IDS."""
    data = json.load(open(geo_path))
    out = []
    found = set()
    for feat in data["features"]:
        props = feat["properties"]
        region_id = props.get("iso_3166_2")
        if not region_id or region_id not in REGION_IDS or region_id in found:
            continue

        rings = _flatten_rings(feat["geometry"])
        if not rings:
            continue

        label_lon = props.get("longitude")
        label_lat = props.get("latitude")
        if label_lon is None or label_lat is None:
            label_lon, label_lat = _bbox_centroid(rings)

        found.add(region_id)
        out.append({
            "id": region_id,
            "country": region_id.split("-")[0],
            "name": props.get("name") or region_id,
            "labelLon": round(float(label_lon), 2),
            "labelLat": round(float(label_lat), 2),
            "rings": rings,
        })

    missing = REGION_IDS - found
    if missing:
        print("warning: curated region ids not found in admin-1 data:", sorted(missing))
    return out


def load_overrides():
    """Hand-curated pipeline input at scripts/overrides.json — not fetched, not generated.
    Tolerates a missing file so the pipeline still runs before it exists."""
    if not os.path.exists(OVERRIDES_PATH):
        return {"countries": {}, "regions": {}}
    with open(OVERRIDES_PATH) as f:
        data = json.load(f)
    return {"countries": data.get("countries", {}), "regions": data.get("regions", {})}


def apply_country_overrides(langs, territories, country_overrides):
    """A curated entry replaces whatever CLDR had for that language/territory pair outright —
    these exist specifically to correct or fill a known CLDR gap. Only applied to territories
    with known population; returns the count of entries applied."""
    applied = 0
    for lang_code, terr_map in country_overrides.items():
        for terr_code, entry in terr_map.items():
            if terr_code not in territories:
                continue
            langs.setdefault(lang_code, {})[terr_code] = {
                "pct": float(entry["pct"]),
                "status": entry.get("status"),
            }
            applied += 1
    return applied


def resolve_region_overrides(region_overrides, region_ids):
    """Drops any curated region-language entry whose region id has no geometry (e.g. a curated
    id Natural Earth doesn't carry under that exact code). lang -> {region_id: {pct, status}}."""
    resolved = {}
    for lang_code, region_map in region_overrides.items():
        kept = {rid: entry for rid, entry in region_map.items() if rid in region_ids}
        if kept:
            resolved[lang_code] = kept
    return resolved


def assemble_languages(langs, territories, region_langs=None):
    region_langs = region_langs or {}
    result = []
    for code in set(langs) | set(region_langs):
        terr_map = langs.get(code, {})
        speakers = 0
        territories_out = {}
        for terr, entry in terr_map.items():
            pop = territories.get(terr, {}).get("population", 0)
            speakers += int(pop * entry["pct"] / 100.0)
            territories_out[terr] = {"pct": entry["pct"], "status": entry["status"]}
        regions_out = {
            rid: {"pct": float(entry["pct"]), "status": entry.get("status")}
            for rid, entry in region_langs.get(code, {}).items()
        }
        # Region shares are a subset of a country's population already counted above — they
        # don't add to `speakers`, or a regional language would double-count toward it.
        if not territories_out and not regions_out:
            continue
        entry = {
            "code": code,
            "name": code,  # Swift resolves a localized display name at runtime via Locale
            "speakers": speakers,
            "territories": territories_out,
        }
        if regions_out:
            entry["regions"] = regions_out
        result.append(entry)
    result.sort(key=lambda l: l["speakers"], reverse=True)
    return result


def write(path, obj):
    with open(path, "w") as f:
        json.dump(obj, f, separators=(",", ":"))
    print("wrote %s (%.2f MB)" % (path, os.path.getsize(path) / 1e6))


def report(territories, langs, countries, languages, overrides_applied=0, regions=None):
    regions = regions or []
    world_pop = sum(t["population"] for t in territories.values())
    geo_ids = {c["id"] for c in countries}
    print()
    print("=== self-check ===")
    print("territories: %d          countries with geometry: %d" % (len(territories), len(countries)))
    print("languages:   %d          world population sum: %.2fB" % (len(languages), world_pop / 1e9))
    print("country-level overrides applied: %d" % overrides_applied)
    print("curated regions with geometry: %d / %d" % (len(regions), len(REGION_IDS)))
    with_regions = sum(1 for l in languages if l.get("regions"))
    print("languages with region-level data: %d" % with_regions)
    no_geo = [c for c in territories if c not in geo_ids]
    print("territories in CLDR with no geometry match: %d" % len(no_geo))
    for code in ("es", "en", "zh", "fr", "pt"):
        terr_map = langs.get(code, {})
        speakers = sum(territories[t]["population"] * e["pct"] / 100.0
                       for t, e in terr_map.items() if t in territories)
        pct_world = 100 * speakers / world_pop if world_pop else 0
        print("  %s -> %d territories, %.0fM speakers (%.1f%% of world)"
              % (code, len(terr_map), speakers / 1e6, pct_world))
    print("spot checks:")
    for lang, terr in (("es", "ES"), ("pt", "BR"), ("en", "NG"), ("hi", "IN"), ("fr", "CA")):
        entry = langs.get(lang, {}).get(terr)
        print("  %s in %s: %s" % (lang, terr, entry["pct"] if entry else None))


def main():
    geo_path = fetch(GEO_URL, "countries.geojson")
    cldr_path = fetch(CLDR_URL, "cldr.xml")
    admin1_path = fetch(ADMIN1_URL, "admin1.geojson")

    territories, langs = build_language_data(cldr_path)
    countries = build_geometry(geo_path)
    regions = build_regions(admin1_path)

    # Attach Natural Earth names to the territory table; drop CLDR
    # territories we have no polygon for (small dependencies, mostly).
    for c in countries:
        if c["id"] in territories:
            territories[c["id"]]["name"] = c["name"]
    territories = {k: v for k, v in territories.items() if "name" in v}

    overrides = load_overrides()
    overrides_applied = apply_country_overrides(langs, territories, overrides["countries"])
    region_ids = {r["id"] for r in regions}
    region_langs = resolve_region_overrides(overrides["regions"], region_ids)

    languages = assemble_languages(langs, territories, region_langs)

    os.makedirs(OUT, exist_ok=True)
    write(os.path.join(OUT, "territories.json"), {"version": 1, "territories": territories})
    write(os.path.join(OUT, "languages.json"), {"version": 1, "languages": languages})
    write(os.path.join(OUT, "geometry.json"), {"version": 1, "countries": countries})
    write(os.path.join(OUT, "regions.json"), {"version": 1, "regions": regions})

    report(territories, langs, countries, languages, overrides_applied, regions)


if __name__ == "__main__":
    main()
