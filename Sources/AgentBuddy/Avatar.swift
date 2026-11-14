import SwiftUI

extension Color {
    /// Lime from the reference. Fill colour works in both appearances; text needs a darker shade on light backgrounds.
    static let lime = Color(red: 0.84, green: 0.95, blue: 0.29)
    static let limeText = Color(nsColor: NSColor(name: nil) { a in
        a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.84, green: 0.95, blue: 0.29, alpha: 1)
            : NSColor(red: 0.36, green: 0.48, blue: 0.0, alpha: 1)
    })
}

/// The little robot that represents a session. Mood follows the session state.
struct Avatar: View {
    enum Mood { case working, idle, alert }
    static let palette: [Color] = [
        Color(red: 0.31, green: 0.55, blue: 0.97), Color(red: 0.95, green: 0.48, blue: 0.69),
        Color(red: 0.97, green: 0.64, blue: 0.29), Color(red: 0.65, green: 0.49, blue: 0.95),
        Color(red: 0.24, green: 0.79, blue: 0.76), Color(red: 0.42, green: 0.80, blue: 0.37),
        Color(red: 0.94, green: 0.42, blue: 0.36), Color(red: 0.91, green: 0.77, blue: 0.28),
    ]

    let color: Color
    var mood: Mood = .idle
    var size: CGFloat = 34

    @State private var bob = false

    var body: some View {
        let u = size / 34
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 6 * u, style: .continuous)
                    .fill(color)
                    .frame(width: 28 * u, height: 25 * u)
                face(u)
            }
            HStack(spacing: 8 * u) {
                UnevenRoundedRectangle(bottomLeadingRadius: 2 * u, bottomTrailingRadius: 2 * u).fill(color).frame(width: 5 * u, height: 8 * u)
                UnevenRoundedRectangle(bottomLeadingRadius: 2 * u, bottomTrailingRadius: 2 * u).fill(color).frame(width: 5 * u, height: 8 * u)
            }
            .offset(y: -2 * u)
        }
        .offset(y: bob ? -2 * u : 0)
        .animation(mood == .idle ? .default : .easeInOut(duration: mood == .alert ? 0.35 : 0.9).repeatForever(autoreverses: true), value: bob)
        .frame(width: size, height: size)
        .onAppear { bob = mood != .idle }
        .onChange(of: mood) { _, m in bob = m != .idle }
        .accessibilityHidden(true)
    }

    @ViewBuilder private func face(_ u: CGFloat) -> some View {
        let ink = Color(red: 0.11, green: 0.14, blue: 0.2)
        VStack(spacing: 4 * u) {
            HStack(spacing: 7 * u) {
                eye(ink, u)
                eye(ink, u)
            }
            RoundedRectangle(cornerRadius: 1 * u)
                .fill(ink)
                .frame(width: mood == .alert ? 6 * u : 10 * u, height: mood == .alert ? 5 * u : 2.5 * u)
        }
        .offset(y: 1 * u)
    }

    @ViewBuilder private func eye(_ ink: Color, _ u: CGFloat) -> some View {
        switch mood {
        case .idle:
            RoundedRectangle(cornerRadius: 1 * u).fill(ink).frame(width: 5 * u, height: 2 * u)   // sleepy
        case .alert:
            RoundedRectangle(cornerRadius: 1.5 * u).fill(ink).frame(width: 5 * u, height: 7 * u)
        case .working:
            RoundedRectangle(cornerRadius: 1.5 * u).fill(ink)
                .phaseAnimator([1.0, 1.0, 1.0, 0.15]) { v, p in v.scaleEffect(y: p) }           // blink
                .frame(width: 4 * u, height: 6 * u)
        }
    }
}
