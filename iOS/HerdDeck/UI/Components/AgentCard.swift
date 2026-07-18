import SwiftUI

struct AgentCard: View {
    let agent: HerdrAgent
    let openConsole: () -> Void

    var body: some View {
        Button(action: openConsole) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.status(agent.agentStatus).opacity(0.13))
                        Image(systemName: runtimeSymbol)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.status(agent.agentStatus))
                    }
                    .frame(width: 46, height: 46)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(agent.displayName)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(agent.runtimeLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    StatusPill(status: agent.agentStatus, detail: agent.customStatus)
                }

                Text(agent.locationLabel)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 8) {
                    Label(agent.focused ? "Focused" : "Background", systemImage: agent.focused ? "scope" : "circle.dotted")
                    Spacer()
                    Label("Open console", systemImage: "terminal")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(agent.focused ? Color.herdCyan.opacity(0.34) : Color.white.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the live terminal for this agent")
    }

    private var runtimeSymbol: String {
        let runtime = "\(agent.agent ?? "") \(agent.displayAgent ?? "")".lowercased()
        if runtime.contains("claude") { return "sparkles" }
        if runtime.contains("codex") { return "chevron.left.forwardslash.chevron.right" }
        return "terminal.fill"
    }
}
