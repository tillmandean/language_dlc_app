import SwiftUI

/// The "DLC" readout overlaid at the top of the globe: how much of the world is unlocked,
/// broken down, plus a chip per selected language to remove it without opening the picker.
struct StatsHUD: View {
    var state: AppState

    @State private var toastText: String?
    @State private var toastTask: Task<Void, Never>?

    /// World-coverage fractions that trigger a brief "achievement" toast when first crossed.
    private static let milestones: [Double] = [0.10, 0.25, 0.50, 0.75]

    private let store = DataStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if state.selected.isEmpty {
                emptyState
            } else {
                headline
                progressBar
                secondaryRow
                chips
            }

            if let toastText {
                toast(toastText)
            }
        }
        .padding(16)
        .background {
            // Navy tint over the material, so the panel stays part of the palette instead of
            // picking up whatever colour the globe happens to be showing behind it.
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 20).fill(Theme.navySurface.opacity(0.55)))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.hairline, lineWidth: 1))
        }
        .animation(.snappy(duration: 0.35), value: state.stats.fraction)
        .animation(.snappy(duration: 0.35), value: state.selected)
        .onChange(of: state.stats.fraction) { old, new in checkMilestone(old: old, new: new) }
    }

    // MARK: - Sections

    private var emptyState: some View {
        Text("Pick a language to see what you unlock.")
            .font(.subheadline)
            .foregroundStyle(Theme.sky)
            .accessibilityIdentifier("worldSummary")
            .allowsHitTesting(false)
    }

    private var headline: some View {
        Text("World unlocked: \(percentString)")
            .font(.title2.bold().monospacedDigit())
            .foregroundStyle(.white)
            .contentTransition(.numericText())
            .accessibilityIdentifier("worldSummary")
            .allowsHitTesting(false)
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                Capsule()
                    .fill(hueGradient)
                    .frame(width: geo.size.width * state.stats.fraction)
            }
        }
        .frame(height: 6)
        .allowsHitTesting(false)
    }

    private var secondaryRow: some View {
        Text("\(formattedCount(state.stats.peopleReached)) people · " +
             "\(state.stats.countriesAny) countries · official in \(state.stats.countriesOfficial)" as String)
            .font(.caption)
            .foregroundStyle(.white.opacity(0.7))
            .allowsHitTesting(false)
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(state.selected, id: \.self, content: chip)
            }
        }
    }

    private func chip(for code: String) -> some View {
        Button {
            state.toggle(code)
        } label: {
            HStack(spacing: 4) {
                Text(store.languagesByCode[code]?.displayName ?? code)
                Image(systemName: "xmark").font(.caption2)
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(.white)
            .background(chipColor(for: code).opacity(0.85), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(store.languagesByCode[code]?.displayName ?? code), remove")
    }

    private func toast(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(.white)
            .background(Theme.sky.opacity(0.28), in: Capsule())
            .transition(.move(edge: .top).combined(with: .opacity))
            .allowsHitTesting(false)
    }

    // MARK: - Color

    private var hueGradient: LinearGradient {
        let colors = state.selected.map(chipColor)
        return LinearGradient(colors: colors.isEmpty ? [Theme.sky, Theme.skyBright] : colors,
                              startPoint: .leading, endPoint: .trailing)
    }

    private func chipColor(for code: String) -> Color {
        Color(hue: Double(state.hue(for: code)), saturation: 0.75, brightness: 0.9)
    }

    // MARK: - Formatting

    private var percentString: String {
        String(format: "%.1f%%", state.stats.fraction * 100)
    }

    private func formattedCount(_ n: Int) -> String {
        switch n {
        case 1_000_000_000...: return String(format: "%.1fB", Double(n) / 1e9)
        case 1_000_000...:     return String(format: "%.0fM", Double(n) / 1e6)
        case 1_000...:         return String(format: "%.0fK", Double(n) / 1e3)
        default:                return "\(n)"
        }
    }

    // MARK: - Achievement toast

    private func checkMilestone(old: Double, new: Double) {
        guard let crossed = Self.milestones.last(where: { old < $0 && new >= $0 }) else { return }
        toastTask?.cancel()
        toastText = "🎉 \(Int(crossed * 100))% of the world unlocked!"
        toastTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy(duration: 0.35)) { toastText = nil }
        }
    }
}

#Preview {
    ZStack {
        Theme.background.ignoresSafeArea()
        VStack {
            StatsHUD(state: AppState())
            Spacer()
        }
    }
}
