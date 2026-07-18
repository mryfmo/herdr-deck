import SwiftUI

struct HerdOverviewView: View {
    @EnvironmentObject private var appState: AppState
    let openConsole: () -> Void
    @State private var launchProfile: AgentProfile?

    private var blockedCount: Int { appState.agents.filter { $0.agentStatus == .blocked }.count }
    private var workingCount: Int { appState.agents.filter { $0.agentStatus == .working }.count }
    private var doneCount: Int { appState.agents.filter { $0.agentStatus == .done }.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 18) {
                    hero
                    statusStrip
                    if appState.agents.isEmpty {
                        EmptyStateView(
                            symbol: "terminal",
                            title: "No detected agents",
                            message: "Start Claude Code or Codex in Herdr, or launch a reusable profile below."
                        )
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
                    } else {
                        agentSection
                    }
                    profileSection
                    missionPulse
                }
                .padding(16)
            }
            .refreshable { await appState.refresh() }
            .background(HerdDeckBackground())
            .navigationTitle("Herd")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    AppMark(size: 31)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ConnectionPill(phase: appState.connectionPhase)
                }
            }
            .sheet(item: $launchProfile) { profile in
                StartProfileSheet(profile: profile) { paneID in
                    appState.selectedPaneID = paneID
                    openConsole()
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private var hero: some View {
        GlassCard(padding: 20) {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    SectionEyebrow(text: "Control room")
                    Text(greeting)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                    Text(heroMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.07), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: min(CGFloat(workingCount + blockedCount) / max(CGFloat(appState.agents.count), 1), 1))
                        .stroke(
                            AngularGradient(colors: [.herdViolet, .herdCyan, .herdMint], center: .center),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(appState.agents.count)")
                            .font(.title2.weight(.bold).monospacedDigit())
                        Text("agents")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 86, height: 86)
            }
        }
    }

    private var statusStrip: some View {
        HStack(spacing: 10) {
            MetricChip(value: workingCount, label: "Working", color: .herdCyan)
            MetricChip(value: blockedCount, label: "Input", color: .herdAmber)
            MetricChip(value: doneCount, label: "Done", color: .herdMint)
        }
    }

    private var agentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionEyebrow(text: "Live agents")
                Spacer()
                Text("Blocked first")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            LazyVStack(spacing: 12) {
                ForEach(appState.agents) { agent in
                    AgentCard(agent: agent) {
                        appState.selectedPaneID = agent.paneId
                        openConsole()
                    }
                }
            }
        }
    }

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionEyebrow(text: "Reusable profiles")
            if appState.profiles.isEmpty {
                Text("No launch profiles are configured on the Gateway.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(appState.profiles) { profile in
                            Button {
                                launchProfile = profile
                            } label: {
                                ProfileTile(profile: profile)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .contentMargins(.horizontal, 1, for: .scrollContent)
            }
        }
    }

    private var missionPulse: some View {
        GlassCard {
            HStack(spacing: 14) {
                Image(systemName: "scope")
                    .font(.title2)
                    .foregroundStyle(.herdViolet)
                    .frame(width: 46, height: 46)
                    .background(.herdViolet.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mission pulse")
                        .font(.headline)
                    Text("\(appState.missions.filter { $0.status == .running }.count) running · \(appState.missions.count) recorded")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    private var greeting: String {
        if blockedCount > 0 { return "Your herd needs you" }
        if workingCount > 0 { return "Agents are in motion" }
        return "Ready for the next mission"
    }

    private var heroMessage: String {
        if blockedCount > 0 { return "\(blockedCount) agent\(blockedCount == 1 ? " is" : "s are") waiting for input." }
        if workingCount > 0 { return "Monitor progress, then drop into the terminal only when needed." }
        return "Launch a profile or orchestrate Claude and Codex through AGMSG."
    }
}

private struct MetricChip: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(value)")
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(color.opacity(0.15)))
    }
}

private struct ProfileTile: View {
    let profile: AgentProfile

    var body: some View {
        let accent = Color.profileAccent(profile.accent)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: profile.runtime == "claude-code" ? "sparkles" : "chevron.left.forwardslash.chevron.right")
                    .font(.headline)
                    .foregroundStyle(accent)
                Spacer()
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(accent)
            }
            Text(profile.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Text("\(profile.modelLabel) · \(profile.effortLabel)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(15)
        .frame(width: 210, height: 128, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(accent.opacity(0.2)))
    }
}

struct StartProfileSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let profile: AgentProfile
    let launched: (String) -> Void
    @State private var projectPath = ""
    @State private var name = ""
    @State private var prompt = ""
    @State private var focus = true
    @State private var isStarting = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    LabeledContent("Runtime", value: profile.runtime)
                    LabeledContent("Model", value: profile.modelLabel)
                    LabeledContent("Effort", value: profile.effortLabel)
                }
                Section("Launch") {
                    TextField("/Users/me/Developer/project", text: $projectPath)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Optional Herdr name", text: $name)
                    TextField("Optional initial prompt", text: $prompt, axis: .vertical)
                        .lineLimit(3...8)
                    Toggle("Focus after launch", isOn: $focus)
                }
                if let error {
                    Section { Text(error).foregroundStyle(.herdAmber) }
                }
                Section {
                    Button {
                        Task { await start() }
                    } label: {
                        HStack {
                            if isStarting { ProgressView() }
                            Text(isStarting ? "Launching…" : "Launch in Herdr")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(projectPath.isEmpty || isStarting)
                }
            }
            .navigationTitle(profile.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onAppear {
                projectPath = appState.selectedAgent?.foregroundCwd ?? appState.selectedAgent?.cwd ?? ""
            }
        }
    }

    private func start() async {
        isStarting = true
        error = nil
        defer { isStarting = false }
        do {
            let response = try await appState.startProfile(StartProfileRequest(
                profileId: profile.id,
                projectPath: projectPath,
                name: name.isEmpty ? nil : name,
                prompt: prompt.isEmpty ? nil : prompt,
                split: "right",
                focus: focus
            ))
            dismiss()
            launched(response.agent.paneId)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
