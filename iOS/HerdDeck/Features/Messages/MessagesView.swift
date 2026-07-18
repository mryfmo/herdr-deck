import SwiftUI

enum MessageTimestamp {
    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let standard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func date(from value: String) -> Date? {
        fractional.date(from: value) ?? standard.date(from: value)
    }
}

struct MessagesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedAgentFilter: String?
    @State private var draft = ""
    @State private var fromAgent = "orchestrator"
    @State private var toAgent = "builder"
    @State private var isSending = false
    @FocusState private var composerFocused: Bool

    private var selectedTeam: String? { appState.selectedTeam ?? appState.teams.first }
    private var memberNames: [String] {
        let members = appState.teamMembers.map(\.name)
        let messageNames = appState.messages.flatMap { [$0.fromAgent, $0.toAgent] }
        return Array(Set(members + messageNames)).sorted()
    }
    private var sendableMemberNames: [String] {
        // Mission control recipients are durable completion mailboxes owned by
        // the Gateway. Keep them visible in history/filtering, but out of the
        // human message composer to avoid accidental MISSION_DONE traffic.
        memberNames.filter { !$0.lowercased().hasPrefix("herddeck-") }
    }
    private var visibleMessages: [AgmsgMessage] {
        // AGMSG's stable API already returns the requested window oldest-first.
        // Message IDs are opaque strings, so lexical sorting would corrupt order
        // for both decimal IDs ("10" before "2") and future non-numeric IDs.
        guard let selectedAgentFilter else { return appState.messages }
        return appState.messages.filter { $0.fromAgent == selectedAgentFilter || $0.toAgent == selectedAgentFilter }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                teamRail
                if selectedTeam == nil {
                    EmptyStateView(
                        symbol: "bubble.left.and.bubble.right",
                        title: "No AGMSG teams",
                        message: "Start a mission or join agents to an AGMSG team on the Mac."
                    )
                    .frame(maxHeight: .infinity)
                } else if visibleMessages.isEmpty {
                    EmptyStateView(
                        symbol: "tray",
                        title: "No messages yet",
                        message: "Task handoffs, status replies, and artifact references will appear here."
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    messageTimeline
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if selectedTeam != nil { composer }
            }
            .background(HerdDeckBackground())
            .navigationTitle("Messages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("All agents") { selectedAgentFilter = nil }
                        ForEach(memberNames, id: \.self) { name in
                            Button(name) { selectedAgentFilter = name }
                        }
                    } label: {
                        Label(selectedAgentFilter ?? "All", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .task(id: selectedTeam) {
                if let selectedTeam { await appState.loadMessages(team: selectedTeam) }
                configureParticipants()
            }
            .refreshable {
                if let selectedTeam { await appState.loadMessages(team: selectedTeam, agent: selectedAgentFilter) }
            }
            .onChange(of: appState.teamMembers) { _, _ in configureParticipants() }
        }
    }

    private var teamRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(appState.teams, id: \.self) { team in
                    Button {
                        appState.selectedTeam = team
                        selectedAgentFilter = nil
                        Task { await appState.loadMessages(team: team) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "person.3.fill")
                            Text(team)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(team == selectedTeam ? Color.herdCyan : .secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(team == selectedTeam ? Color.herdCyan.opacity(0.1) : Color.white.opacity(0.04), in: Capsule())
                        .overlay(Capsule().stroke(team == selectedTeam ? Color.herdCyan.opacity(0.28) : .clear))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
    }

    private var messageTimeline: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(visibleMessages) { message in
                        AgmsgMessageCard(message: message)
                            .id(message.id)
                    }
                }
                .padding(14)
            }
            .onChange(of: visibleMessages.count) { _, _ in
                if let last = visibleMessages.last?.id {
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
            .onAppear {
                if let last = visibleMessages.last?.id { proxy.scrollTo(last, anchor: .bottom) }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ParticipantMenu(label: "From", selection: $fromAgent, names: sendableMemberNames)
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ParticipantMenu(label: "To", selection: $toAgent, names: sendableMemberNames.filter { $0 != fromAgent })
                Spacer()
                Text("AGMSG")
                    .font(.caption2.bold())
                    .tracking(1.1)
                    .foregroundStyle(.herdViolet)
            }
            HStack(alignment: .bottom, spacing: 9) {
                TextField("Task, status, or artifact reference…", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($composerFocused)
                    .submitLabel(.send)
                    .onSubmit {
                        guard !isSending else { return }
                        Task { await send() }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 15))
                Button {
                    Task { await send() }
                } label: {
                    Group {
                        if isSending { ProgressView().tint(.white) }
                        else { Image(systemName: "paperplane.fill") }
                    }
                    .frame(width: 44, height: 44)
                    .foregroundStyle(.white)
                    .background(.herdViolet, in: RoundedRectangle(cornerRadius: 14))
                }
                .disabled(isSending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || fromAgent.isEmpty || toAgent.isEmpty)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider().opacity(0.25) }
    }

    private func configureParticipants() {
        guard !sendableMemberNames.isEmpty else { return }
        if !sendableMemberNames.contains(fromAgent) {
            fromAgent = sendableMemberNames.first(where: { $0.localizedCaseInsensitiveContains("orchestrator") })
                ?? sendableMemberNames[0]
        }
        if toAgent == fromAgent || !sendableMemberNames.contains(toAgent) {
            toAgent = sendableMemberNames.first(where: { $0 != fromAgent && $0.localizedCaseInsensitiveContains("builder") })
                ?? sendableMemberNames.first(where: { $0 != fromAgent })
                ?? ""
        }
    }

    private func send() async {
        guard !isSending else { return }
        guard let team = selectedTeam else { return }
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        isSending = true
        do {
            try await appState.sendMessage(team: team, from: fromAgent, to: toAgent, body: body)
            draft = ""
            Haptic.success()
        } catch {
            appState.presentedError = error.localizedDescription
            Haptic.error()
        }
        isSending = false
    }
}

private struct AgmsgMessageCard: View {
    let message: AgmsgMessage

    private var accent: Color {
        if message.fromAgent.localizedCaseInsensitiveContains("orchestrator") { return .herdViolet }
        if message.fromAgent.localizedCaseInsensitiveContains("builder") { return .herdCyan }
        return .herdMint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Circle().fill(accent).frame(width: 7, height: 7)
                Text(message.fromAgent)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(accent)
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(message.toAgent)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(
                    MessageTimestamp.date(from: message.at)
                        .map { Self.timeFormatter.string(from: $0) }
                        ?? message.at
                )
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            messageBody
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("#\(message.id)")
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(accent.opacity(0.13)))
    }

    @ViewBuilder
    private var messageBody: some View {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        if let attributed = try? AttributedString(markdown: message.body, options: options) {
            Text(attributed)
                .font(.subheadline)
                .lineSpacing(3)
        } else {
            Text(message.body)
                .font(.subheadline)
                .lineSpacing(3)
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct ParticipantMenu: View {
    let label: String
    @Binding var selection: String
    let names: [String]

    var body: some View {
        Menu {
            ForEach(names, id: \.self) { name in
                Button(name) { selection = name }
            }
        } label: {
            HStack(spacing: 5) {
                Text(label).foregroundStyle(.secondary)
                Text(selection.isEmpty ? "—" : selection)
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(.white.opacity(0.06), in: Capsule())
        }
    }
}
