//
//  ContentView.swift
//  languageDLC
//
//  The app's root screen: the map texture wrapped on a rotatable globe, the stats HUD above it
//  and the control row below, plus the sheets they open — language picker, country detail,
//  attribution, and the share sheet. `showList` swaps the globe for the VoiceOver-friendly
//  country list, which is the accessible route to the same data.
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
            Theme.background.ignoresSafeArea()

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
                    let hit = MapRasterizer.shared.feature(atU: u, v: v)
                    state.focused = hit
                    if hit != nil { haptic.impactOccurred() }
                }, captureHandler: $captureGlobe)
                .ignoresSafeArea()
                .accessibilityLabel(globeAccessibilityLabel)

                if texture == nil {
                    ProgressView().tint(Theme.sky)
                }

                VStack {
                    StatsHUD(state: state)
                    Spacer()
                    controls
                }
                .padding()
            }
        }
        .sheet(item: focusedFeature) { feature in
            CountryDetailSheet(feature: feature, state: state)
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
                .foregroundStyle(state.focused == nil ? Theme.sky.opacity(0.85) : .white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Theme.navySurface.opacity(0.75), in: Capsule())
                .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
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
            .tint(Theme.sky)
            .fixedSize()

            listToggleButton

            Button {
                showAttribution = true
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.bordered)
            .tint(Theme.sky)
            .accessibilityLabel("Data & credits")

            Button {
                shareGlobe()
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            .tint(Theme.sky)
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
        .tint(Theme.sky)
        // In list mode this button floats over the rows, and `.bordered` is translucent — the
        // row's text showed straight through it. An opaque navy backing makes it read as a
        // control sitting on top rather than a rendering glitch.
        .background(Theme.navy, in: Capsule())
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
        let store = DataStore.shared
        switch state.focused {
        case nil:                     return "Tap a country"
        case .country(let code):      return store.territories[code]?.name ?? code
        case .region(let id, _):      return store.regionsById[id]?.name ?? id
        }
    }

    /// `.sheet(item:)` needs a binding; `AppState` is `@Observable`, not a `Binding` source.
    /// `MapFeature` is `Identifiable`, so nothing else has to be wrapped.
    private var focusedFeature: Binding<MapFeature?> {
        Binding(get: { state.focused }, set: { state.focused = $0 })
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

}

#Preview {
    ContentView()
}
