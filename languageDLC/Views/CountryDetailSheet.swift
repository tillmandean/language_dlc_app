import SwiftUI

/// Tap a country, see what would unlock it, add the language — the app's discovery loop.
///
/// Also handles a tap that landed inside a curated sub-national region (a Swiss canton, Quebec,
/// Texas): the same layout, driven by that region's own language percentages instead of its
/// country's, with a row up to the country so the whole-country view is never more than a tap
/// away. Only a minority of countries have curated regions, so most taps still land on a country.
struct CountryDetailSheet: View {
    let feature: MapFeature
    var state: AppState

    private let store = DataStore.shared

    var body: some View {
        NavigationStack {
            List {
                Section { header }
                    .navyRows()
                if case .region(_, let country) = feature {
                    Section { parentCountryRow(country) }
                        .navyRows()
                }
                Section(languagesSectionTitle) {
                    ForEach(languagesHere, id: \.language.code) { entry in
                        languageRow(entry.language, entry.presence)
                    }
                }
                .navyRows()
            }
            .navyList()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.navy)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(flag).font(.system(size: 40))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.title2.bold())
                    if let population {
                        Text("\(population.formatted()) people")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textMuted)
                    }
                }
            }

            let fraction = coverage?.coverage ?? 0
            VStack(alignment: .leading, spacing: 6) {
                Text("Unlocked: \(Int((fraction * 100).rounded()))%")
                    .font(.headline)
                ProgressView(value: fraction)
                    .tint(tint)
            }
        }
        .padding(.vertical, 4)
    }

    /// Shown only for a region: retargets the sheet at the country containing it, so tapping a
    /// canton is not a dead end for anyone who wanted Switzerland.
    private func parentCountryRow(_ country: String) -> some View {
        Button {
            state.focused = .country(country)
        } label: {
            HStack(spacing: 12) {
                Text("Part of")
                    .foregroundStyle(Theme.textMuted)
                Text(store.territories[country]?.name ?? country)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textMuted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Part of \(store.territories[country]?.name ?? country), show the whole country")
    }

    private var tint: Color {
        guard let dominant = coverage?.dominantLanguage else { return .gray }
        return Color(hue: Double(state.hue(for: dominant)), saturation: 0.8, brightness: 0.85)
    }

    // MARK: - Language rows

    private func languageRow(_ language: Language, _ presence: LanguagePresence) -> some View {
        let isSelected = state.selected.contains(language.code)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(language.displayName)
                if let status = presence.status {
                    Text(status.label)
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)
                }
                ProgressView(value: presence.pct / 100)
                    .tint(isSelected
                          ? Color(hue: Double(state.hue(for: language.code)),
                                 saturation: 0.8, brightness: 0.85)
                          : .gray.opacity(0.5))
            }
            Spacer()
            Text("\(Int(presence.pct.rounded()))%")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Theme.textMuted)
            Button {
                state.toggle(language.code)
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? Theme.skyBright : Theme.sky.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Data

    private var title: String {
        switch feature {
        case .country(let code):
            return store.territories[code]?.name ?? code
        case .region(let id, _):
            return store.regionsById[id]?.name ?? id
        }
    }

    /// A region carries its own Wikidata population; a country its CLDR one. Either can be
    /// missing or zero, in which case the line is dropped rather than showing "0 people".
    private var population: Int? {
        let value: Int?
        switch feature {
        case .country(let code): value = store.territories[code]?.population
        case .region(let id, _): value = store.regionsById[id]?.population
        }
        return (value ?? 0) > 0 ? value : nil
    }

    private var coverage: CountryCoverage? {
        switch feature {
        case .country(let code): return state.coverage[code]
        case .region(let id, _): return state.regionCoverage[id]
        }
    }

    private var languagesSectionTitle: String {
        switch feature {
        case .country: return "Languages spoken here"
        // Named so the numbers below are not mistaken for the country's. The curated regional
        // figures are hand estimates — the attribution sheet says so — and they differ from the
        // country's on purpose; that difference is the whole reason these regions exist.
        case .region:  return "Languages spoken in this region"
        }
    }

    /// Every language present here over 1%, selected ones first, then by strength. Regions read
    /// from each language's curated `regions` map; countries from its `territories` map.
    private var languagesHere: [(language: Language, presence: LanguagePresence)] {
        store.languages.compactMap { language -> (Language, LanguagePresence)? in
            let presence: LanguagePresence?
            switch feature {
            case .country(let code): presence = language.territories[code]
            case .region(let id, _): presence = language.regions?[id]
            }
            guard let presence, presence.pct >= 1 else { return nil }
            return (language, presence)
        }.sorted { a, b in
            let aSelected = state.selected.contains(a.0.code)
            let bSelected = state.selected.contains(b.0.code)
            if aSelected != bSelected { return aSelected }
            return a.1.pct > b.1.pct
        }
    }

    /// The ISO alpha-2 code as a flag emoji: each letter offset into the regional-indicator range.
    /// A region shows its country's flag — there are no flag emoji below the country level.
    private var flag: String {
        String(String.UnicodeScalarView(
            feature.territory.uppercased().unicodeScalars
                .compactMap { Unicode.Scalar(0x1F1E6 + $0.value - 65) }
        ))
    }
}
