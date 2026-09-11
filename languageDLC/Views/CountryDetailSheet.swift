import SwiftUI

/// Wraps a territory code so `AppState.focused` (a plain `String?`) can drive `.sheet(item:)`.
struct FocusedTerritory: Identifiable, Equatable {
    let code: String
    var id: String { code }
}

/// Tap a country, see what would unlock it, add the language — the app's discovery loop.
struct CountryDetailSheet: View {
    let code: String
    var state: AppState

    private let store = DataStore.shared

    var body: some View {
        NavigationStack {
            List {
                Section { header }
                Section("Languages spoken here") {
                    ForEach(languagesHere, id: \.language.code) { entry in
                        languageRow(entry.language, entry.presence)
                    }
                }
            }
            .navigationTitle(territory?.name ?? code)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(flag).font(.system(size: 40))
                VStack(alignment: .leading, spacing: 2) {
                    Text(territory?.name ?? code).font(.title2.bold())
                    if let population = territory?.population {
                        Text("\(population.formatted()) people")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
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
                        .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
            Button {
                state.toggle(language.code)
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? .green : .accentColor)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Data

    private var territory: Territory? { store.territories[code] }
    private var coverage: CountryCoverage? { state.coverage[code] }

    /// Every language spoken here over 1%, selected ones first, then by strength.
    private var languagesHere: [(language: Language, presence: LanguagePresence)] {
        store.languages.compactMap { language -> (Language, LanguagePresence)? in
            guard let presence = language.territories[code], presence.pct >= 1 else { return nil }
            return (language, presence)
        }.sorted { a, b in
            let aSelected = state.selected.contains(a.0.code)
            let bSelected = state.selected.contains(b.0.code)
            if aSelected != bSelected { return aSelected }
            return a.1.pct > b.1.pct
        }
    }

    /// The ISO alpha-2 code as a flag emoji: each letter offset into the regional-indicator range.
    private var flag: String {
        String(String.UnicodeScalarView(
            code.uppercased().unicodeScalars.compactMap { Unicode.Scalar(0x1F1E6 + $0.value - 65) }
        ))
    }
}
