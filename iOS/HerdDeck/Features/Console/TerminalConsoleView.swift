import SwiftUI
import UIKit

@MainActor
struct TerminalConsoleView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var mosh = MoshSessionController()
    @StateObject private var gatewayFeed = TerminalFeed()

    @State private var output = ""
    @State private var revision: UInt64 = 0
    @State private var isTruncated = false
    @State private var draft = ""
    @State private var isSending = false
    @State private var terminalError: String?
    @State private var showInspector = false
    @State private var terminalColumns = 100
    @State private var terminalRows = 34
    @FocusState private var composerFocused: Bool

    private var selectedAgent: HerdrAgent? { appState.selectedAgent }
    private var paneID: String? { selectedAgent?.paneId ?? appState.selectedPaneID }
    private var renderMode: TerminalRenderMode { appState.terminalPreferences.renderMode }
    private var usesMoshTerminal: Bool { renderMode == .terminal && appState.terminalRoute == .mosh }
    private var activeFeed: TerminalFeed { usesMoshTerminal ? mosh.feed : gatewayFeed }
    private var effectiveRoute: TerminalRoute { usesMoshTerminal ? .mosh : .gateway }

    private var consoleTaskID: String {
        "\(paneID ?? "none"):\(renderMode.rawValue):\(effectiveRoute.rawValue)"
    }

    private var contextualNotice: String? {
        if renderMode != .terminal && appState.terminalRoute == .mosh {
            return "Rich and Raw remain on the HTTPS control plane. Switch to Terminal to use Mosh on cellular."
        }
        return appState.terminalRouteNotice
    }

    var body: some View {
        NavigationStack {
            Group {
                if appState.agents.isEmpty {
                    EmptyStateView(
                        symbol: "terminal",
                        title: "No terminal to open",
                        message: "Launch an agent profile or start a mission first."
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    VStack(spacing: 0) {
                        agentRail
                        terminalHeader
                        if let contextualNotice {
                            transportNotice(contextualNotice)
                        }
                        outputSurface
                        keyRail
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        composer
                    }
                }
            }
            .background(HerdDeckBackground())
            .navigationTitle("Console")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ConnectionPill(phase: appState.connectionPhase)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showInspector = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .disabled(selectedAgent == nil)
                }
            }
            .sheet(isPresented: $showInspector) {
                if let selectedAgent {
                    AgentInspectorView(agent: selectedAgent)
                        .presentationDetents([.medium])
                        .presentationDragIndicator(.visible)
                }
            }
            .task(id: consoleTaskID) {
                await runConsole()
            }
            .onDisappear {
                mosh.disconnect()
            }
        }
    }

    private var agentRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                ForEach(appState.agents) { agent in
                    Button {
                        appState.selectedPaneID = agent.paneId
                        resetDisplay()
                    } label: {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(Color.status(agent.agentStatus))
                                .frame(width: 7, height: 7)
                            Text(agent.displayName)
                                .lineLimit(1)
                            if agent.agentStatus == .blocked {
                                Image(systemName: "exclamationmark")
                                    .font(.caption2.bold())
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(agent.paneId == paneID ? .primary : .secondary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(
                            agent.paneId == paneID ? Color.white.opacity(0.12) : Color.white.opacity(0.045),
                            in: Capsule()
                        )
                        .overlay(Capsule().stroke(agent.paneId == paneID ? Color.herdCyan.opacity(0.3) : .clear))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
    }

    private var terminalHeader: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedAgent?.displayName ?? "Terminal")
                        .font(.subheadline.weight(.semibold))
                    Text(selectedAgent?.locationLabel ?? "—")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                if let selectedAgent {
                    StatusPill(status: selectedAgent.agentStatus, detail: selectedAgent.customStatus)
                }
            }

            HStack(spacing: 7) {
                ConsoleInfoPill(
                    symbol: appState.networkInterface.symbolName,
                    text: appState.networkInterface.label,
                    tint: appState.networkInterface == .cellular ? .herdAmber : .herdMint
                )
                ConsoleInfoPill(
                    symbol: effectiveRoute.symbolName,
                    text: usesMoshTerminal ? mosh.phase.label : effectiveRoute.label,
                    tint: usesMoshTerminal ? .herdViolet : .herdCyan
                )
                Spacer(minLength: 4)
                Picker("Rendering", selection: renderModeBinding) {
                    ForEach(TerminalRenderMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 230)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 10)
        .background(Color.herdPanel.opacity(0.9))
        .overlay(alignment: .bottom) { Divider().opacity(0.25) }
    }

    @ViewBuilder
    private var outputSurface: some View {
        switch renderMode {
        case .rich:
            RichTerminalOutputView(text: output, error: terminalError)
        case .terminal:
            ZStack(alignment: .bottomLeading) {
                TerminalEmulatorView(
                    feed: activeFeed,
                    onInput: handleTerminalInput,
                    onResize: handleTerminalResize
                )
                .id("\(paneID ?? "none"):\(effectiveRoute.rawValue)")

                if let terminalError {
                    terminalErrorBubble(terminalError)
                }
            }
            .background(Color.herdInk)
        case .raw:
            RawTerminalOutputView(
                output: output,
                revision: revision,
                isTruncated: isTruncated,
                error: terminalError
            )
        }
    }

    private var keyRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                TerminalKey(title: "esc", keys: ["esc"], action: sendKeys)
                TerminalKey(title: "tab", keys: ["tab"], action: sendKeys)
                TerminalKey(title: "⌃C", keys: ["ctrl+c"], role: .warning, action: sendKeys)
                TerminalKey(title: "⌃D", keys: ["ctrl+d"], role: .warning, action: sendKeys)
                TerminalKey(title: "←", keys: ["left"], action: sendKeys)
                TerminalKey(title: "↓", keys: ["down"], action: sendKeys)
                TerminalKey(title: "↑", keys: ["up"], action: sendKeys)
                TerminalKey(title: "→", keys: ["right"], action: sendKeys)
                TerminalKey(title: "enter", keys: ["enter"], role: .accent, action: sendKeys)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider().opacity(0.25) }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Send text to the active agent…", text: $draft, axis: .vertical)
                .font(.body)
                .lineLimit(1...5)
                .focused($composerFocused)
                .submitLabel(.send)
                .onSubmit { Task { await sendDraft() } }
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.08)))

            Button {
                Task { await sendDraft() }
            } label: {
                Group {
                    if isSending {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.headline.bold())
                    }
                }
                .frame(width: 46, height: 46)
                .foregroundStyle(.white)
                .background(
                    canSendDraft ? Color.herdViolet : Color.secondary.opacity(0.4),
                    in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                )
            }
            .disabled(isSending || !canSendDraft)
            .accessibilityLabel("Send to terminal")
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 5)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider().opacity(0.25) }
    }

    private var canSendDraft: Bool {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if usesMoshTerminal {
            return mosh.phase == .connected || mosh.phase == .connecting
        }
        return true
    }

    private var renderModeBinding: Binding<TerminalRenderMode> {
        Binding(
            get: { appState.terminalPreferences.renderMode },
            set: { mode in
                appState.updateTerminalPreferences { $0.renderMode = mode }
                resetDisplay()
            }
        )
    }

    private func transportNotice(_ message: String) -> some View {
        Label(message, systemImage: "info.circle.fill")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.herdAmber.opacity(0.08))
            .overlay(alignment: .bottom) { Divider().opacity(0.2) }
    }

    private func terminalErrorBubble(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.herdAmber)
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(10)
    }

    private func runConsole() async {
        guard let paneID else { return }
        resetDisplay()
        if usesMoshTerminal {
            await runMoshTerminal(paneID: paneID)
        } else {
            await pollGateway(paneID: paneID, mode: renderMode)
        }
    }

    private func runMoshTerminal(paneID: String) async {
        defer { mosh.disconnect() }
        var retryDelay = 1.0

        while !Task.isCancelled {
            switch mosh.phase {
            case .idle, .failed(_):
                await mosh.connect(
                    paneID: paneID,
                    columns: terminalColumns,
                    rows: terminalRows
                ) {
                    try await appState.createMoshSession(
                        paneID: paneID,
                        columns: terminalColumns,
                        rows: terminalRows
                    )
                }
                if case let .failed(message) = mosh.phase {
                    terminalError = message
                    try? await Task.sleep(for: .seconds(retryDelay))
                    retryDelay = min(retryDelay * 1.8, 12)
                } else if case let .unavailable(message) = mosh.phase {
                    terminalError = message
                    return
                } else {
                    terminalError = nil
                    retryDelay = 1
                }
            case .unavailable(let message):
                terminalError = message
                return
            case .bootstrapping, .connecting, .connected:
                if case .connected = mosh.phase { terminalError = nil }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func pollGateway(paneID: String, mode: TerminalRenderMode) async {
        var lastText = ""
        while !Task.isCancelled {
            do {
                let read: PaneReadResult
                switch mode {
                case .terminal:
                    read = try await appState.readPane(paneID, source: "visible", lines: 400, format: "ansi")
                case .rich:
                    read = try await appState.readPane(paneID, source: "recent_unwrapped", lines: 400, format: "text")
                case .raw:
                    read = try await appState.readPane(paneID, source: "recent", lines: 400, format: "text")
                }
                guard !Task.isCancelled else { return }

                if read.revision != revision || read.text != lastText {
                    output = read.text
                    revision = read.revision
                    isTruncated = read.truncated
                    lastText = read.text
                    if mode == .terminal {
                        gatewayFeed.send(read.text, reset: true)
                    }
                }
                terminalError = nil
            } catch is CancellationError {
                return
            } catch {
                terminalError = error.localizedDescription
            }
            let milliseconds = appState.configuration?.terminalPollMilliseconds ?? GatewayConfiguration.defaultPollMilliseconds
            try? await Task.sleep(for: .milliseconds(milliseconds))
        }
    }

    private func handleTerminalInput(_ data: Data) {
        guard !data.isEmpty else { return }
        if usesMoshTerminal {
            mosh.send(data)
            return
        }
        guard let paneID else { return }
        let mapped = TerminalInputMapper.map(data)
        guard !mapped.text.isEmpty || !mapped.keys.isEmpty else { return }
        Task {
            do {
                try await appState.sendInput(paneID: paneID, text: mapped.text, keys: mapped.keys)
            } catch {
                terminalError = error.localizedDescription
                Haptic.error()
            }
        }
    }

    private func handleTerminalResize(columns: Int, rows: Int) {
        terminalColumns = max(columns, 20)
        terminalRows = max(rows, 6)
        if usesMoshTerminal {
            mosh.resize(columns: terminalColumns, rows: terminalRows)
        }
    }

    private func sendKeys(_ keys: [String]) {
        guard let paneID else { return }
        if usesMoshTerminal {
            guard mosh.phase == .connected || mosh.phase == .connecting else {
                terminalError = "Mosh is still connecting."
                return
            }
            mosh.send(TerminalInputMapper.encode(keys: keys))
            Haptic.tap()
            return
        }

        Task {
            do {
                try await appState.sendInput(paneID: paneID, keys: keys)
                Haptic.tap()
            } catch {
                terminalError = error.localizedDescription
                Haptic.error()
            }
        }
    }

    private func sendDraft() async {
        guard let paneID else { return }
        let text = draft.trimmingCharacters(in: .newlines)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isSending = true
        terminalError = nil
        defer { isSending = false }

        do {
            if usesMoshTerminal {
                var data = Data(text.utf8)
                data.append(0x0d)
                mosh.send(data)
            } else {
                try await appState.sendInput(paneID: paneID, text: text, keys: ["enter"])
            }
            draft = ""
            Haptic.success()
        } catch {
            terminalError = error.localizedDescription
            Haptic.error()
        }
    }

    private func resetDisplay() {
        output = ""
        revision = 0
        isTruncated = false
        terminalError = nil
        gatewayFeed.clear()
    }
}

private struct RawTerminalOutputView: View {
    let output: String
    let revision: UInt64
    let isTruncated: Bool
    let error: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 0) {
                    if output.isEmpty && error == nil {
                        HStack(spacing: 10) {
                            ProgressView().tint(.herdCyan)
                            Text("Reading raw output…")
                                .foregroundStyle(.secondary)
                        }
                        .padding(18)
                    } else {
                        Text(output.isEmpty ? " " : output)
                            .font(.system(size: 12.5, weight: .regular, design: .monospaced))
                            .foregroundStyle(Color(red: 0.84, green: 0.90, blue: 0.94))
                            .lineSpacing(2.2)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(14)
                    }
                    Color.clear.frame(width: 1, height: 1).id("terminal-bottom")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(
                LinearGradient(
                    colors: [Color.black.opacity(0.74), Color.herdInk.opacity(0.96)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 6) {
                    if isTruncated { Text("trimmed") }
                    Text("r\(revision)")
                }
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(7)
            }
            .overlay(alignment: .bottomLeading) {
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.herdAmber)
                        .padding(10)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding(10)
                }
            }
            .onChange(of: output) { _, _ in
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo("terminal-bottom", anchor: .bottom)
                }
            }
        }
    }
}

private struct ConsoleInfoPill: View {
    let symbol: String
    let text: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(tint.opacity(0.1), in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.18)))
            .lineLimit(1)
    }
}

private struct TerminalKey: View {
    enum Role { case normal, accent, warning }
    let title: String
    let keys: [String]
    var role: Role = .normal
    let action: ([String]) -> Void

    private var foreground: Color {
        switch role {
        case .normal: .primary
        case .accent: .herdCyan
        case .warning: .herdAmber
        }
    }

    var body: some View {
        Button { action(keys) } label: {
            Text(title)
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .foregroundStyle(foreground)
                .padding(.horizontal, 11)
                .frame(height: 34)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(foreground.opacity(0.14)))
        }
        .buttonStyle(.plain)
    }
}

private struct AgentInspectorView: View {
    let agent: HerdrAgent

    var body: some View {
        NavigationStack {
            List {
                Section("Identity") {
                    LabeledContent("Herdr name", value: agent.name ?? "—")
                    LabeledContent("Runtime", value: agent.runtimeLabel)
                    LabeledContent("Status", value: agent.agentStatus.label)
                }
                Section("Placement") {
                    LabeledContent("Workspace", value: agent.workspaceId)
                    LabeledContent("Tab", value: agent.tabId)
                    LabeledContent("Pane", value: agent.paneId)
                }
                Section("Process") {
                    LabeledContent("Directory", value: agent.locationLabel)
                    LabeledContent("Revision", value: String(agent.revision))
                    if let session = agent.agentSession {
                        LabeledContent("Session", value: session.value)
                    }
                }
                if let labels = agent.stateLabels, !labels.isEmpty {
                    Section("State labels") {
                        ForEach(labels.keys.sorted(), id: \.self) { key in
                            LabeledContent(key, value: labels[key] ?? "")
                        }
                    }
                }
            }
            .navigationTitle(agent.displayName)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

enum Haptic {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}
