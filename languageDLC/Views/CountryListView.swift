import SwiftUI

/// VoiceOver has no way to hit-test a sphere, so this is the accessible route to the same
/// data the globe shows: every territory, sorted by how unlocked it is, opening the same
/// detail sheet on tap.
///
/// Curated sub-national regions are tappable on the globe, so they appear here too — indented
/// directly beneath the country they belong to, rather than competing with countries for a place
/// in the ranking. Without them this list would be missing something the globe offers, which is
/// exactly the gap it exists to close.
struct CountryListView: View {
    var state: AppState

    private let store = DataStore.shared

    var body: some View {
        List(rows) { row in
            Button {
                state.focused = row.feature
            } label: {
                content(for: row)
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.clear)
            .listRowSeparatorTint(Theme.hairline)
            // The territory or region code, which is stable regardless of how the list is
            // currently ordered — the spoken label moves with coverage, so it can't address a row.
            .accessibilityIdentifier(row.id)
            .accessibilityLabel(accessibilityLabel(for: row))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .accessibilityIdentifier("countryList")
    }

    private func content(for row: Row) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(row.isRegion ? .subheadline : .body)
                    .foregroundStyle(row.isRegion ? Theme.textMuted : .white)
                if let dominant = row.coverage?.dominantLanguage,
                   let language = store.languagesByCode[dominant] {
                    Text(language.displayName)
                        .font(.caption)
                        .foregroundStyle(Theme.sky.opacity(0.85))
                }
            }
            Spacer()
            // Unlocked countries get the accent; the long tail of 0% stays quiet so the list
            // can be skimmed for what's actually been covered.
            Text(percentString(row.coverage?.coverage ?? 0))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle((row.coverage?.coverage ?? 0) > 0
                                 ? Theme.skyBright : .white.opacity(0.35))
        }
        .padding(.leading, row.isRegion ? 20 : 0)
        .contentShape(Rectangle())
    }

    /// VoiceOver reads rows out of context, so a region has to name its country — "Québec" alone
    /// does not say where it sits, and the indent that conveys that visually is not spoken.
    private func accessibilityLabel(for row: Row) -> String {
        let pct = Int(((row.coverage?.coverage ?? 0) * 100).rounded())
        var label = row.name
        if case .region(_, let country) = row.feature {
            label += ", in \(store.territories[country]?.name ?? country)"
        }
        label += ", \(pct)% unlocked"
        if let dominant = row.coverage?.dominantLanguage,
           let language = store.languagesByCode[dominant] {
            label += ", mostly \(language.displayName)"
        }
        return label
    }

    private func percentString(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    private struct Row: Identifiable {
        let feature: MapFeature
        let name: String
        let coverage: CountryCoverage?
        let isRegion: Bool

        var id: String { feature.id }
    }

    /// Countries by highest coverage first, ties broken alphabetically so the order is stable;
    /// each country's curated regions follow it immediately, ordered the same way among
    /// themselves. Region ids never collide with country codes, so `id` stays unique.
    private var rows: [Row] {
        let regionsByCountry = Dictionary(grouping: store.regions, by: \.country)

        return store.territories
            .map { Row(feature: .country($0.key), name: $0.value.name,
                       coverage: state.coverage[$0.key], isRegion: false) }
            .sorted(by: Self.byCoverageThenName)
            .flatMap { country -> [Row] in
                guard let regions = regionsByCountry[country.feature.territory] else { return [country] }
                let regionRows = regions
                    .map { Row(feature: .region(id: $0.id, country: $0.country), name: $0.name,
                               coverage: state.regionCoverage[$0.id], isRegion: true) }
                    .sorted(by: Self.byCoverageThenName)
                return [country] + regionRows
            }
    }

    private static func byCoverageThenName(_ a: Row, _ b: Row) -> Bool {
        let ac = a.coverage?.coverage ?? 0
        let bc = b.coverage?.coverage ?? 0
        if ac != bc { return ac > bc }
        return a.name < b.name
    }
}

#Preview {
    CountryListView(state: AppState())
}
