//
//  ContentView.swift
//  languageDLC
//
//  Milestone B: the map texture wrapped on a rotatable globe, with a country detail sheet
//  and the language picker. The tapped-country readout is temporary; Phase 8 replaces it
//  with the stats HUD.
//

import SwiftUI
import UIKit

struct ContentView: View {
    @State private var state = AppState()
    @State private var texture: CGImage?
    @State private var showPicker = false
    @State private var showList = false
    @State private var showAttribution = false
    @State private var captureGlobe: (() -> UIImage?)?
    @State private var shareImage: UIImage?

    private let haptic = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if showList {
                CountryListView(state: state)

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        listToggleButton
                    }
                }
                .padding()
            } else {
                GlobeView(texture: texture, onTap: { u, v in
                    let territory = MapRasterizer.shared.territory(atU: u, v: v)
                    state.focused = territory
                    if territory != nil { haptic.impactOccurred() }
                }, captureHandler: $captureGlobe)
                .ignoresSafeArea()
                .accessibilityLabel(globeAccessibilityLabel)

                if texture == nil {
                    ProgressView().tint(.white)
                }

                VStack {
                    StatsHUD(state: state)
                    Spacer()
                    controls
                }
                .padding()
            }
        }
        .sheet(item: focusedTerritory) { entry in
            CountryDetailSheet(code: entry.code, state: state)
        }
        .sheet(isPresented: $showPicker) {
            LanguagePickerSheet(state: state)
        }
        .sheet(isPresented: $showAttribution) {
            AttributionSheet()
        }
        .sheet(isPresented: Binding(get: { shareImage != nil }, set: { if !$0 { shareImage = nil } })) {
            if let shareImage { ActivityView(activityItems: [shareImage]) }
        }
        .task(id: renderKey) {
            let colors = state.fillColors()
            let regionColors = state.regionFillColors()
            texture = await Task.detached(priority: .userInitiated) {
                MapRasterizer.shared.renderTexture(colors: colors,
                                                   ocean: Palette.ocean,
                                                   lockedLand: Palette.lockedLand,
                                                   borders: Palette.borders,
                                                   regionColors: regionColors)
            }.value
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Text(focusLabel)
                .font(.headline)
                .foregroundStyle(.white)
                .accessibilityIdentifier("focusedTerritory")

            // Centred when the row fits, which it now does with the calibration button gone.
            // The scrolling version is still there as the fallback, because at the largest
            // accessibility text sizes "Languages" alone can outgrow a narrow screen.
            ViewThatFits(in: .horizontal) {
                controlRow
                ScrollView(.horizontal, showsIndicators: false) { controlRow }
            }
        }
    }

    private var controlRow: some View {
        HStack(spacing: 12) {
            Button {
                showPicker = true
            } label: {
                Label("Languages", systemImage: "globe")
            }
            .buttonStyle(.borderedProminent)
            .fixedSize()

            listToggleButton

            Button {
                showAttribution = true
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.bordered)
            .tint(.white)
            .accessibilityLabel("Data & credits")

            Button {
                shareGlobe()
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            .tint(.white)
            .disabled(state.selected.isEmpty || texture == nil)
            .accessibilityLabel("Share")
        }
        .padding(.horizontal, 2)   // room for the focus ring/shadow at the row's edges
    }

    private var listToggleButton: some View {
        Button {
            showList.toggle()
        } label: {
            Image(systemName: showList ? "globe.americas.fill" : "list.bullet")
        }
        .buttonStyle(.bordered)
        .tint(.white)
        .accessibilityLabel(showList ? "Globe" : "List")
        .accessibilityHint("Switch to a VoiceOver-friendly list of countries")
    }

    private func shareGlobe() {
        guard let globeImage = captureGlobe?() else { return }
        shareImage = ShareCardRenderer.makeCard(globe: globeImage, state: state)
    }

    /// Re-render whenever the selection changes.
    private var renderKey: String {
        state.selected.joined(separator: ",")
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

    /// VoiceOver can't hit-test the sphere, so its label states the numbers instead and points
    /// at the accessible alternative.
    private var globeAccessibilityLabel: String {
        let s = state.stats
        let pct = String(format: "%.1f", s.fraction * 100)
        return "World map, not accessible to VoiceOver. \(pct) percent of the world unlocked, " +
            "\(s.countriesAny) countries, official in \(s.countriesOfficial). " +
            "Use the List button to browse countries instead."
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
