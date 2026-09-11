import SwiftUI

/// VoiceOver has no way to hit-test a sphere, so this is the accessible route to the same
/// data the globe shows: every territory, sorted by how unlocked it is, opening the same
/// detail sheet on tap.
struct CountryListView: View {
    var state: AppState

    private let store = DataStore.shared

    var body: some View {
        List(rows, id: \.code) { row in
            Button {
                state.focused = row.code
            } label: {
                content(for: row)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel(for: row))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .accessibilityIdentifier("countryList")
    }

    private func content(for row: Row) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.territory.name)
                    .foregroundStyle(.white)
                if let dominant = row.coverage?.dominantLanguage,
                   let language = store.languagesByCode[dominant] {
                    Text(language.displayName)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            Spacer()
            Text(percentString(row.coverage?.coverage ?? 0))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.white.opacity(0.8))
        }
        .contentShape(Rectangle())
    }

    private func accessibilityLabel(for row: Row) -> String {
        let pct = Int(((row.coverage?.coverage ?? 0) * 100).rounded())
        if let dominant = row.coverage?.dominantLanguage,
           let language = store.languagesByCode[dominant] {
            return "\(row.territory.name), \(pct)% unlocked, mostly \(language.displayName)"
        }
        return "\(row.territory.name), \(pct)% unlocked"
    }

    private func percentString(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    private struct Row {
        let code: String
        let territory: Territory
        let coverage: CountryCoverage?
    }

    /// Highest coverage first, ties broken alphabetically so the order is stable.
    private var rows: [Row] {
        store.territories
            .map { Row(code: $0.key, territory: $0.value, coverage: state.coverage[$0.key]) }
            .sorted { a, b in
                let ac = a.coverage?.coverage ?? 0
                let bc = b.coverage?.coverage ?? 0
                if ac != bc { return ac > bc }
                return a.territory.name < b.territory.name
            }
    }
}

#Preview {
    CountryListView(state: AppState())
}
