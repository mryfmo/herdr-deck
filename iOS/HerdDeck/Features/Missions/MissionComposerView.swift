import SwiftUI

struct MissionComposerView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let started: (MissionRecord) -> Void

    @State private var title = ""
    @State private var goal = ""
    @State private var projectPath = ""
    @State private var team = "herddeck"
    @State private var maxRounds = 8
    @State private var orchestratorID = ""
    @State private var executorIDs: Set<String> = []
    @State private var deliveryAssist = true
    @State private var isStarting = false
    @State private var error: String?
    @FocusState private var focusedField: Field?

    enum Field { case title, goal, project, team }

    private var orchestrators: [AgentProfile] { appState.profiles.filter { $0.role == "orchestrator" } }
    private var executors: [AgentProfile] { appState.profiles.filter { $0.role != "orchestrator" } }
    private var canStart: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 &&
        goal.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10 &&
        !projectPath.isEmpty && !team.isEmpty && !orchestratorID.isEmpty && !executorIDs.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    intentCard
                    roleCard
                    protocolCard
                    launchCard
                }
                .padding(16)
            }
            .background(HerdDeckBackground())
            .navigationTitle("New mission")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onAppear { configureDefaults() }
        }
    }

    private var intentCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 15) {
                SectionEyebrow(text: "Mission intent")
                TextField("Mission title", text: $title)
                    .font(.title3.weight(.semibold))
                    .focused($focusedField, equals: .title)
                Divider().opacity(0.35)
                TextField("Describe the outcome, constraints, and definition of done…", text: $goal, axis: .vertical)
                    .lineLimit(5...12)
                    .focused($focusedField, equals: .goal)
                Divider().opacity(0.35)
                LabelledField(label: "Project", symbol: "folder.fill") {
                    TextField("/Users/me/Developer/project", text: $projectPath)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                        .focused($focusedField, equals: .project)
                }
                LabelledField(label: "AGMSG team", symbol: "person.3.fill") {
                    TextField("herddeck", text: $team)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                        .focused($focusedField, equals: .team)
                }
            }
        }
    }

    private var roleCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionEyebrow(text: "Agent topology")
                Text("Orchestrator")
                    .font(.subheadline.weight(.semibold))
                if orchestrators.isEmpty {
                    Text("No orchestrator profile is configured.")
                        .font(.caption)
                        .foregroundStyle(.herdAmber)
                } else {
                    ForEach(orchestrators) { profile in
                        ProfileChoice(
                            profile: profile,
                            selected: profile.id == orchestratorID,
                            mode: .single
                        ) { orchestratorID = profile.id }
                    }
                }

                Divider().opacity(0.35)
                Text("Autonomous executors")
                    .font(.subheadline.weight(.semibold))
                if executors.isEmpty {
                    Text("No executor profile is configured.")
                        .font(.caption)
                        .foregroundStyle(.herdAmber)
                } else {
                    ForEach(executors) { profile in
                        ProfileChoice(
                            profile: profile,
                            selected: executorIDs.contains(profile.id),
                            mode: .multiple
                        ) {
                            if executorIDs.contains(profile.id) { executorIDs.remove(profile.id) }
                            else if executorIDs.count < 4 { executorIDs.insert(profile.id) }
                        }
                    }
                }
            }
        }
    }

    private var protocolCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionEyebrow(text: "Coordination protocol")
                Stepper(value: $maxRounds, in: 1...30) {
                    HStack {
                        Label("Maximum rounds", systemImage: "arrow.triangle.2.circlepath")
                        Spacer()
                        Text("\(maxRounds)").font(.body.monospacedDigit().weight(.semibold))
                    }
                }
                Toggle(isOn: $deliveryAssist) {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("Delivery assist", systemImage: "bolt.horizontal.circle.fill")
                        Text("Nudge an agent to read new AGMSG mail.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "shield.lefthalf.filled")
                        .foregroundStyle(.herdMint)
                    Text("Executors inherit the configured workspace-write sandbox. HerdDeck never enables dangerous approval bypass flags automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var launchCard: some View {
        VStack(spacing: 10) {
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.herdAmber)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                Task { await startMission() }
            } label: {
                HStack {
                    if isStarting { ProgressView().tint(.white) }
                    Text(isStarting ? "Starting agents…" : "Start mission")
                    Spacer()
                    Image(systemName: "arrow.up.right.circle.fill")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(HerdDeckPrimaryButtonStyle())
            .disabled(!canStart || isStarting)
        }
    }

    private func configureDefaults() {
        if projectPath.isEmpty {
            projectPath = appState.selectedAgent?.foregroundCwd ?? appState.selectedAgent?.cwd ?? ""
        }
        if orchestratorID.isEmpty { orchestratorID = orchestrators.first?.id ?? "" }
        if executorIDs.isEmpty, let first = executors.first { executorIDs.insert(first.id) }
        if title.isEmpty { focusedField = .title }
    }

    private func startMission() async {
        isStarting = true
        error = nil
        defer { isStarting = false }
        do {
            let mission = try await appState.startMission(StartMissionRequest(
                title: title,
                goal: goal,
                projectPath: projectPath,
                team: team,
                maxRounds: maxRounds,
                orchestratorProfileId: orchestratorID,
                executorProfileIds: Array(executorIDs).sorted(),
                deliveryAssist: deliveryAssist
            ))
            Haptic.success()
            dismiss()
            started(mission)
        } catch {
            self.error = error.localizedDescription
            Haptic.error()
        }
    }
}

private struct LabelledField<Content: View>: View {
    let label: String
    let symbol: String
    let content: Content

    init(label: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 12) {
            Label(label, systemImage: symbol)
                .font(.subheadline.weight(.medium))
            Spacer(minLength: 8)
            content
        }
    }
}

private struct ProfileChoice: View {
    enum Mode: Equatable { case single, multiple }
    let profile: AgentProfile
    let selected: Bool
    let mode: Mode
    let action: () -> Void

    var body: some View {
        let accent = Color.profileAccent(profile.accent)
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: profile.runtime == "claude-code" ? "sparkles" : "chevron.left.forwardslash.chevron.right")
                    .foregroundStyle(accent)
                    .frame(width: 34, height: 34)
                    .background(accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("\(profile.modelLabel) · \(profile.effortLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: selected ? (mode == .single ? "largecircle.fill.circle" : "checkmark.square.fill") : (mode == .single ? "circle" : "square"))
                    .foregroundStyle(selected ? accent : .secondary)
            }
            .padding(12)
            .background(selected ? accent.opacity(0.08) : Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(selected ? accent.opacity(0.25) : .white.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }
}
