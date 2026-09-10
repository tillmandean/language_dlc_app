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

GEO_URL = "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_50m_admin_0_countries.geojson"
CLDR_URL = "https://raw.githubusercontent.com/unicode-org/cldr/main/common/supplemental/supplementalData.xml"

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


def assemble_languages(langs, territories):
    result = []
    for code, terr_map in langs.items():
        speakers = 0
        territories_out = {}
        for terr, entry in terr_map.items():
            pop = territories.get(terr, {}).get("population", 0)
            speakers += int(pop * entry["pct"] / 100.0)
            territories_out[terr] = {"pct": entry["pct"], "status": entry["status"]}
        if not territories_out:
            continue
        result.append({
            "code": code,
            "name": code,  # Swift resolves a localized display name at runtime via Locale
            "speakers": speakers,
            "territories": territories_out,
        })
    result.sort(key=lambda l: l["speakers"], reverse=True)
    return result


def write(path, obj):
    with open(path, "w") as f:
        json.dump(obj, f, separators=(",", ":"))
    print("wrote %s (%.2f MB)" % (path, os.path.getsize(path) / 1e6))


def report(territories, langs, countries, languages):
    world_pop = sum(t["population"] for t in territories.values())
    geo_ids = {c["id"] for c in countries}
    print()
    print("=== self-check ===")
    print("territories: %d          countries with geometry: %d" % (len(territories), len(countries)))
    print("languages:   %d          world population sum: %.2fB" % (len(languages), world_pop / 1e9))
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

    territories, langs = build_language_data(cldr_path)
    countries = build_geometry(geo_path)

    # Attach Natural Earth names to the territory table; drop CLDR
    # territories we have no polygon for (small dependencies, mostly).
    for c in countries:
        if c["id"] in territories:
            territories[c["id"]]["name"] = c["name"]
    territories = {k: v for k, v in territories.items() if "name" in v}

    languages = assemble_languages(langs, territories)

    os.makedirs(OUT, exist_ok=True)
    write(os.path.join(OUT, "territories.json"), {"version": 1, "territories": territories})
    write(os.path.join(OUT, "languages.json"), {"version": 1, "languages": languages})
    write(os.path.join(OUT, "geometry.json"), {"version": 1, "countries": countries})

    report(territories, langs, countries, languages)


if __name__ == "__main__":
    main()
