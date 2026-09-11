import SwiftUI

/// Search/browse every language, pick the ones you speak. Pinned "Selected" section up top so
/// deselecting never requires scrolling through 479 rows to find where a language landed.
struct LanguagePickerSheet: View {
    var state: AppState

    @State private var query = ""
    @State private var showRare = false
    @State private var showLimitAlert = false

    private let store = DataStore.shared
    private let rareThreshold = 1_000_000

    var body: some View {
        NavigationStack {
            List {
                if !selectedLanguages.isEmpty {
                    Section("Selected") {
                        ForEach(selectedLanguages) { row(for: $0) }
                    }
                }
                Section {
                    ForEach(filteredLanguages) { row(for: $0) }
                } footer: {
                    if !showRare {
                        Text("Languages with under 1M speakers are hidden.")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, prompt: "Search languages")
            .navigationTitle("Languages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Toggle("Show rare languages", isOn: $showRare)
                        .toggleStyle(.button)
                        .font(.caption)
                }
            }
            .alert("Up to 8 languages", isPresented: $showLimitAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Remove one to add another — 8 keeps every globe color distinct.")
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Rows

    private func row(for language: Language) -> some View {
        let isSelected = state.selected.contains(language.code)
        return Button {
            toggle(language)
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(isSelected
                          ? Color(hue: Double(state.hue(for: language.code)),
                                 saturation: 0.75, brightness: 0.9)
                          : Color.gray.opacity(0.35))
                    .frame(width: 12, height: 12)

                VStack(alignment: .leading, spacing: 2) {
                    Text(language.displayName)
                        .foregroundStyle(.primary)
                    if let native = language.nativeName, native != language.displayName {
                        Text(native)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("\(language.territories.count) countries · \(formatted(language.speakers)) speakers")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? .green : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(language.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func toggle(_ language: Language) {
        guard state.selected.contains(language.code) || state.selected.count < AppState.maxSelected
        else {
            showLimitAlert = true
            return
        }
        state.toggle(language.code)
    }

    // MARK: - Data

    /// Selected languages, in selection order (matches their globe color assignment).
    private var selectedLanguages: [Language] {
        state.selected.compactMap { store.languagesByCode[$0] }
    }

    /// Everything else, filtered by the rarity toggle and search — already sorted by speaker
    /// count since `DataStore.languages` is.
    private var filteredLanguages: [Language] {
        store.languages.filter { language in
            !state.selected.contains(language.code)
                && (showRare || language.speakers >= rareThreshold)
                && matches(language, query: query)
        }
    }

    private func matches(_ language: Language, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return language.displayName.localizedCaseInsensitiveContains(query)
            || language.name.localizedCaseInsensitiveContains(query)
            || language.code.localizedCaseInsensitiveContains(query)
            || (language.nativeName?.localizedCaseInsensitiveContains(query) ?? false)
    }

    private func formatted(_ n: Int) -> String {
        switch n {
        case 1_000_000_000...: return String(format: "%.1fB", Double(n) / 1e9)
        case 1_000_000...:     return String(format: "%.0fM", Double(n) / 1e6)
        case 1_000...:         return String(format: "%.0fK", Double(n) / 1e3)
        default:                return "\(n)"
        }
    }
}

#Preview {
    LanguagePickerSheet(state: AppState())
}
