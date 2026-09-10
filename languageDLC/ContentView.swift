//
//  ContentView.swift
//  languageDLC
//
//  Milestone A: a flat equirectangular map, to validate geometry, projection and coloring
//  before any 3D work. Replaced by the globe in Phase 5.
//

import SwiftUI

struct ContentView: View {
    @State private var state = AppState()
    @State private var texture: UIImage?

    private let demoLanguages = ["es", "fr"]

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Color.black
                if let texture {
                    Image(uiImage: texture)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 12) {
                ForEach(demoLanguages, id: \.self) { code in
                    let isOn = state.selected.contains(code)
                    Button(DataStore.shared.languagesByCode[code]?.displayName ?? code) {
                        state.toggle(code)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isOn ? .accentColor : .gray)
                }
            }

            Text(summary)
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding()
        .task(id: state.selected) {
            let colors = state.fillColors()
            let image = await Task.detached(priority: .userInitiated) {
                MapRasterizer.shared.renderTexture(colors: colors,
                                                   ocean: Palette.ocean,
                                                   lockedLand: Palette.lockedLand,
                                                   borders: Palette.borders)
            }.value
            if let image { texture = UIImage(cgImage: image) }
        }
    }

    private var summary: String {
        let s = state.stats
        let pct = String(format: "%.1f%%", s.fraction * 100)
        return "\(pct) of the world · \(s.countriesAny) countries · \(s.countriesOfficial) official"
    }
}

#Preview {
    ContentView()
}
