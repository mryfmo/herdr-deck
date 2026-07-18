import SwiftUI

struct MissionsView: View {
    @EnvironmentObject private var appState: AppState
    let openConsole: (String) -> Void
    @State private var showComposer = false

    private var running: [MissionRecord] { appState.missions.filter { $0.status == .running || $0.status == .starting } }
    private var history: [MissionRecord] { appState.missions.filter { $0.status != .running && $0.status != .starting } }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 18) {
                    missionHero
                    if running.isEmpty && history.isEmpty {
                        EmptyStateView(
                            symbol: "scope",
                            title: "No missions yet",
                            message: "Pair a Fable orchestrator with one or more autonomous Codex executors through AGMSG."
                        )
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
                    }
                    if !running.isEmpty {
                        MissionSection(title: "Active", missions: running, openConsole: openConsole)
                    }
                    if !history.isEmpty {
                        MissionSection(title: "History", missions: history, openConsole: openConsole)
                    }
                }
                .padding(16)
            }
            .refreshable { await appState.refresh() }
            .background(HerdDeckBackground())
            .navigationTitle("Missions")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showComposer = true
                    } label: {
                        Label("New mission", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showComposer) {
                MissionComposerView { mission in
                    if let pane = mission.agents.first?.paneId { openConsole(pane) }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private var missionHero: some View {
        GlassCard(padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionEyebrow(text: "Orchestration")
                        Text("Turn goals into agent work")
                            .font(.title2.weight(.bold))
                        Text("Claude plans and integrates. Codex executes bounded tasks. AGMSG carries durable handoffs.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(colors: [.herdViolet, .herdCyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                }
                Button {
                    showComposer = true
                } label: {
                    Label("Compose mission", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(HerdDeckPrimaryButtonStyle())
            }
        }
    }
}

private struct MissionSection: View {
    let title: String
    let missions: [MissionRecord]
    let openConsole: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionEyebrow(text: title)
            ForEach(missions) { mission in
                MissionCard(mission: mission, openConsole: openConsole)
            }
        }
    }
}

private struct MissionCard: View {
    let mission: MissionRecord
    let openConsole: (String) -> Void
    @State private var expanded = false

    private var statusColor: Color {
        switch mission.status {
        case .starting: .herdCyan
        case .running: .herdMint
        case .completed: .herdMint
        case .failed: .herdRose
        case .stopped: .secondary
        }
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Button {
                    withAnimation(.snappy) { expanded.toggle() }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(statusColor.opacity(0.12))
                            Image(systemName: mission.status == .failed ? "xmark.octagon.fill" : "scope")
                                .foregroundStyle(statusColor)
                        }
                        .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(mission.spec.title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text(mission.spec.team)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 6) {
                            Text(mission.status.label)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(statusColor)
                            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)

                HStack(spacing: 7) {
                    ForEach(mission.agents.prefix(5)) { agent in
                        AgentRoleBadge(agent: agent)
                    }
                    Spacer()
                    Label("\(mission.spec.maxRounds) rounds", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if expanded {
                    Divider().opacity(0.35)
                    Text(mission.spec.goal)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(mission.spec.projectPath)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let control = mission.controlAgmsgName {
                        Label(control, systemImage: "checkmark.message")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    if let error = mission.error {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.herdRose)
                    }
                    if !mission.agents.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(mission.agents) { agent in
                                    Button {
                                        openConsole(agent.paneId)
                                    } label: {
                                        Label(agent.agmsgName, systemImage: "terminal")
                                    }
                                    .buttonStyle(HerdDeckSecondaryButtonStyle())
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct AgentRoleBadge: View {
    let agent: MissionAgent

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: agent.role == "orchestrator" ? "sparkles" : "hammer.fill")
            Text(agent.agmsgName)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(agent.role == "orchestrator" ? Color.herdViolet : Color.herdCyan)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background((agent.role == "orchestrator" ? Color.herdViolet : Color.herdCyan).opacity(0.1), in: Capsule())
    }
}
