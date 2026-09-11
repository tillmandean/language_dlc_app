import SwiftUI

/// The numbers on this app's globe will be argued with — this is the upfront answer to
/// "where did that come from," reachable from an info button next to the language picker.
struct AttributionSheet: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Language & population data") {
                    Text("""
                    Language percentages and territory populations come from the Unicode CLDR \
                    supplemental data. Figures are approximate: they include second-language \
                    speakers, are periodically revised by Unicode's contributors, and can lag \
                    real-world change. A small number of country-level figures — English \
                    comprehension in the Nordics, Russian in Central Asia — are hand-corrected \
                    estimates for known gaps in that dataset.
                    """)
                    Text("Licensed under the Unicode License.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Map data") {
                    Text("Country outlines come from Natural Earth.")
                    Text("""
                    Shaded sub-national regions (Swiss cantons, Belgian and Spanish provinces, \
                    Quebec, several Indian and US states) use Natural Earth boundaries with \
                    hand-curated, approximate language percentages — no authoritative \
                    sub-national source exists at this resolution.
                    """)
                    Text("Natural Earth data is in the public domain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Data & credits")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    AttributionSheet()
}
