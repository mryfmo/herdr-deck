import SwiftUI

extension Color {
    static let herdInk = Color(red: 0.035, green: 0.045, blue: 0.072)
    static let herdPanel = Color(red: 0.075, green: 0.09, blue: 0.13)
    static let herdViolet = Color(red: 0.60, green: 0.45, blue: 1.0)
    static let herdCyan = Color(red: 0.22, green: 0.83, blue: 0.93)
    static let herdMint = Color(red: 0.35, green: 0.91, blue: 0.68)
    static let herdAmber = Color(red: 1.0, green: 0.70, blue: 0.30)
    static let herdRose = Color(red: 1.0, green: 0.39, blue: 0.52)

    static func status(_ status: HerdrAgentStatus) -> Color {
        switch status {
        case .idle: .secondary
        case .working: .herdCyan
        case .blocked: .herdAmber
        case .done: .herdMint
        case .unknown: .herdRose
        }
    }

    static func profileAccent(_ name: String) -> Color {
        switch name.lowercased() {
        case "violet": .herdViolet
        case "cyan": .herdCyan
        case "mint": .herdMint
        case "amber": .herdAmber
        case "rose": .herdRose
        default: .secondary
        }
    }
}

struct HerdDeckBackground: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.herdInk
                RadialGradient(
                    colors: [Color.herdViolet.opacity(0.18), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: proxy.size.width * 0.95
                )
                RadialGradient(
                    colors: [Color.herdCyan.opacity(0.11), .clear],
                    center: .bottomTrailing,
                    startRadius: 0,
                    endRadius: proxy.size.height * 0.75
                )
                Canvas { context, size in
                    let spacing: CGFloat = 32
                    var path = Path()
                    stride(from: CGFloat.zero, through: size.width, by: spacing).forEach { x in
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                    }
                    stride(from: CGFloat.zero, through: size.height, by: spacing).forEach { y in
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                    }
                    context.stroke(path, with: .color(.white.opacity(0.025)), lineWidth: 0.5)
                }
            }
            .ignoresSafeArea()
        }
    }
}

struct AppMark: View {
    var size: CGFloat = 42

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.herdViolet, .herdCyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .stroke(.white.opacity(0.28), lineWidth: 1)
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: size * 0.47, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: .herdViolet.opacity(0.32), radius: size * 0.24, y: size * 0.10)
        .accessibilityLabel("HerdDeck")
    }
}

struct GlassCard<Content: View>: View {
    let padding: CGFloat
    let content: Content

    init(padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.18), .white.opacity(0.04)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: .black.opacity(0.16), radius: 18, y: 10)
    }
}

struct HerdDeckPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .foregroundStyle(.white)
            .background(
                LinearGradient(
                    colors: [.herdViolet, .herdCyan.opacity(0.85)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

struct HerdDeckSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .foregroundStyle(.primary)
            .background(.white.opacity(configuration.isPressed ? 0.07 : 0.11), in: RoundedRectangle(cornerRadius: 13))
    }
}

struct SectionEyebrow: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.bold))
            .tracking(1.5)
            .foregroundStyle(.secondary)
    }
}
