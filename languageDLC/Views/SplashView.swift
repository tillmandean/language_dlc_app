import SwiftUI

/// The launch screen: the logo on the navy it was drawn against, held for a beat while the
/// first globe texture rasterizes behind it, then faded out by `RootView`.
///
/// The logo art already carries its own navy background, so the surrounding color is matched to
/// it exactly (`Theme.navy` is sampled from the file) — the image edge is invisible and the
/// logo reads as painted straight onto the screen.
struct SplashView: View {
    /// Drives the entrance; set true on appear so the logo eases in rather than snapping.
    @State private var entered = false
    /// Sweeps the loading bar 0 -> 1 over the splash's lifetime.
    @State private var progress: CGFloat = 0

    /// Matches `RootView.splashDuration`, minus the fade-out — the bar should be full when the
    /// splash starts leaving, not still travelling.
    static let barDuration: TimeInterval = 1.4

    var body: some View {
        ZStack {
            // Flat, and deliberately so: the logo art carries its own navy background, so
            // anything that lightens the screen behind it — a glow, a gradient — turns that
            // baked-in square into a visible rectangle around the mark. One exact colour, and
            // the logo's edge disappears.
            Theme.navy.ignoresSafeArea()

            VStack(spacing: 40) {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 260, height: 260)
                    .scaleEffect(entered ? 1 : 0.88)
                    .opacity(entered ? 1 : 0)

                loadingBar
                    .opacity(entered ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.55)) { entered = true }
            withAnimation(.easeInOut(duration: Self.barDuration)) { progress = 1 }
        }
        // One label for the whole screen: VoiceOver should announce "Loading", not walk a
        // decorative logo and a progress bar it can't act on.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Language DLC, loading")
        .accessibilityAddTraits(.isImage)
    }

    private var loadingBar: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(.white.opacity(0.12))
            Capsule()
                .fill(LinearGradient(colors: [Theme.sky, Theme.skyBright],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: 140 * progress)
        }
        .frame(width: 140, height: 4)
    }
}

#Preview {
    SplashView()
}
