import SwiftUI

struct StatusPill: View {
    let status: HerdrAgentStatus
    var detail: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: status.symbolName)
            Text(detail ?? status.label)
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(Color.status(status))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.status(status).opacity(0.12), in: Capsule())
        .overlay(Capsule().stroke(Color.status(status).opacity(0.24), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

struct ConnectionPill: View {
    let phase: GatewayConnectionPhase

    private var color: Color {
        switch phase {
        case .connected: .herdMint
        case .connecting: .herdCyan
        case .failed: .herdRose
        case .unconfigured, .disconnected: .secondary
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .shadow(color: color.opacity(0.65), radius: 5)
            Text(phase.label)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.thinMaterial, in: Capsule())
    }
}
