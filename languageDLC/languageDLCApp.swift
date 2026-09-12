//
//  languageDLCApp.swift
//  languageDLC
//
//  Created by Tillman Dean on 9/10/26.
//

import SwiftUI

@main
struct languageDLCApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)   // the app is dark-only by design
        }
    }
}

/// Holds the splash over the app while the bundled data loads, then crossfades to `ContentView`.
///
/// The splash isn't just a timer: `DataStore.shared` decodes four JSON files (the geometry one is
/// the expensive one) and it's a `let` static, so the first thing to touch it pays for all of it.
/// Warming it on a detached task here means that cost lands behind the splash instead of behind
/// a frozen first frame, and `ContentView` is only built once the store is ready.
struct RootView: View {
    @State private var contentReady = false
    @State private var showSplash = true

    /// Floor on how long the splash stays up, so a warm launch still reads as a deliberate
    /// intro rather than a flash of logo.
    private static let minimumSplash: Duration = .seconds(1.5)
    /// Beat between mounting `ContentView` and starting the fade, so the first layout happens
    /// while the splash is still fully opaque.
    private static let mountSettle: Duration = .milliseconds(120)
    private static let fadeDuration: TimeInterval = 0.45

    var body: some View {
        ZStack {
            Theme.navy.ignoresSafeArea()

            if contentReady {
                ContentView()
                    // The content is mounted but still hidden behind the splash, so it must not
                    // be reachable yet: VoiceOver would otherwise read out a screen the user
                    // can't see, and UI tests would find — and try to tap — controls that the
                    // splash is sitting on top of.
                    .accessibilityHidden(showSplash)
            }
            // Above the content and opaque, so whatever the globe is doing underneath — the
            // first texture render in particular — is invisible until it's ready. It takes no
            // touches of its own, so a tap during the fade-out reaches the app rather than
            // vanishing into a view that is on its way out.
            if showSplash {
                SplashView()
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .task {
            // Decode off the main thread; the splash keeps animating.
            async let warm: Void = Task.detached(priority: .userInitiated) {
                _ = DataStore.shared
            }.value
            async let hold: Void = Task.sleep(for: Self.minimumSplash)

            _ = await warm
            try? await hold

            contentReady = true
            try? await Task.sleep(for: Self.mountSettle)
            withAnimation(.easeInOut(duration: Self.fadeDuration)) { showSplash = false }
        }
    }
}
