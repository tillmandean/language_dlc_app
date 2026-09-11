//
//  ContentView.swift
//  languageDLC
//
//  Milestone B: the map texture wrapped on a rotatable globe. The hard-coded language
//  buttons and the tapped-country readout are temporary; Phases 6–8 replace them with the
//  detail sheet, the picker and the HUD.
//

import SwiftUI
import UIKit

struct ContentView: View {
    @State private var state = AppState()
    @State private var texture: CGImage?
    @State private var showCalibration = false

    private let demoLanguages = ["es", "fr"]
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GlobeView(texture: texture) { u, v in
                let territory = MapRasterizer.shared.territory(atU: u, v: v)
                state.focused = territory
                if territory != nil { haptic.impactOccurred() }
            }
            .ignoresSafeArea()
            .sheet(item: focusedTerritory) { entry in
                CountryDetailSheet(code: entry.code, state: state)
            }

            if texture == nil {
                ProgressView().tint(.white)
            }

            VStack {
                Text(summary)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                controls
            }
            .padding()
        }
        .task(id: renderKey) {
            let colors = state.fillColors()
            let calibrating = showCalibration
            texture = await Task.detached(priority: .userInitiated) {
                calibrating
                    ? MapRasterizer.shared.renderCalibrationTexture()
                    : MapRasterizer.shared.renderTexture(colors: colors,
                                                         ocean: Palette.ocean,
                                                         lockedLand: Palette.lockedLand,
                                                         borders: Palette.borders)
            }.value
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Text(focusLabel)
                .font(.headline)
                .foregroundStyle(.white)
                .accessibilityIdentifier("focusedTerritory")

            HStack(spacing: 12) {
                ForEach(demoLanguages, id: \.self) { code in
                    let isOn = state.selected.contains(code)
                    Button(DataStore.shared.languagesByCode[code]?.displayName ?? code) {
                        state.toggle(code)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isOn ? .accentColor : .gray)
                }
                #if DEBUG
                Button(showCalibration ? "Map" : "Calibrate") { showCalibration.toggle() }
                    .buttonStyle(.bordered)
                    .tint(.white)
                #endif
            }
        }
    }

    /// Re-render whenever the selection or the debug texture choice changes.
    private var renderKey: String {
        state.selected.joined(separator: ",") + (showCalibration ? "|cal" : "")
    }

    private var focusLabel: String {
        guard let code = state.focused else { return "Tap a country" }
        return DataStore.shared.territories[code]?.name ?? code
    }

    /// Bridges `AppState.focused` (a plain `String?`) to `.sheet(item:)`, which needs
    /// an `Identifiable` binding.
    private var focusedTerritory: Binding<FocusedTerritory?> {
        Binding(
            get: { state.focused.map(FocusedTerritory.init) },
            set: { state.focused = $0?.code }
        )
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
