//
//  ClaudeInstancesView.swift
//  ClaudePerch
//
//  Mission Control dashboard with session grouping by project
//

import Combine
import SwiftUI

struct ClaudeInstancesView: View {
    @ObservedObject var sessionMonitor: ClaudeSessionMonitor
    @ObservedObject var viewModel: NotchViewModel

    var body: some View {
        if sessionMonitor.instances.isEmpty {
            emptyState
        } else {
            instancesList
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No sessions")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.4))

            Text("Run claude in terminal")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.25))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Session Grouping

    /// Groups sessions by project name, sorted by urgency within each group.
    /// Groups with attention-needing sessions float to the top.
    private var groupedSessions: [(project: String, sessions: [SessionState])] {
        let grouped = Dictionary(grouping: sessionMonitor.instances, by: \.projectName)
        return grouped.map { (project: $0.key, sessions: sortSessions($0.value)) }
            .sorted { groupA, groupB in
                // Groups with attention-needing sessions first
                let urgencyA = groupA.sessions.map { phasePriority($0.phase) }.min() ?? 99
                let urgencyB = groupB.sessions.map { phasePriority($0.phase) }.min() ?? 99
                if urgencyA != urgencyB { return urgencyA < urgencyB }
                return groupA.project < groupB.project
            }
    }

    private func sortSessions(_ sessions: [SessionState]) -> [SessionState] {
        sessions.sorted { a, b in
            let priorityA = phasePriority(a.phase)
            let priorityB = phasePriority(b.phase)
            if priorityA != priorityB { return priorityA < priorityB }
            let dateA = a.lastUserMessageDate ?? a.lastActivity
            let dateB = b.lastUserMessageDate ?? b.lastActivity
            return dateA > dateB
        }
    }

    /// Lower number = higher priority
    private func phasePriority(_ phase: SessionPhase) -> Int {
        switch phase {
        case .waitingForApproval, .processing, .compacting: return 0
        case .waitingForInput: return 1
        case .idle, .ended: return 2
        }
    }

    // MARK: - Instances List

    private var instancesList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 2) {
                let groups = groupedSessions
                let showHeaders = groups.count > 1

                ForEach(Array(groups.enumerated()), id: \.element.project) { index, group in
                    if showHeaders {
                        ProjectGroupHeader(
                            project: group.project,
                            count: group.sessions.count
                        )
                        .padding(.top, index == 0 ? 0 : 8)
                    }

                    ForEach(group.sessions) { session in
                        InstanceRow(
                            session: session,
                            onFocus: { focusSession(session) },
                            onChat: { openChat(session) },
                            onArchive: { archiveSession(session) },
                            onApprove: { approveSession(session) },
                            onReject: { rejectSession(session) },
                            onAnswer: { answer in answerQuestion(session, answer: answer) },
                            onApproveAlways: { approveAlwaysSession(session) }
                        )
                        .id(session.stableId)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: - Actions

    private func focusSession(_ session: SessionState) {
        Task {
            _ = await AppFocusManager.shared.focusSession(
                pid: session.pid,
                cwd: session.cwd,
                isInTmux: session.isInTmux,
                sessionTitle: session.displayTitle,
                sessionId: session.sessionId,
                sessionSummary: session.summary ?? session.windowHint ?? session.firstUserMessage
            )
        }
        // Close the notch after jumping to terminal
        viewModel.notchClose()
    }

    private func openChat(_ session: SessionState) {
        viewModel.showChat(for: session)
    }

    private func answerQuestion(_ session: SessionState, answer: String) {
        sessionMonitor.answerQuestion(sessionId: session.sessionId, selectedOption: answer)
    }

    private func approveSession(_ session: SessionState) {
        sessionMonitor.approvePermission(sessionId: session.sessionId)
    }

    private func approveAlwaysSession(_ session: SessionState) {
        sessionMonitor.approveAlwaysPermission(sessionId: session.sessionId)
    }

    private func rejectSession(_ session: SessionState) {
        sessionMonitor.denyPermission(sessionId: session.sessionId, reason: nil)
    }

    private func archiveSession(_ session: SessionState) {
        sessionMonitor.archiveSession(sessionId: session.sessionId)
    }
}

// MARK: - Instance Row

struct InstanceRow: View {
    let session: SessionState
    let onFocus: () -> Void
    let onChat: () -> Void
    let onArchive: () -> Void
    let onApprove: () -> Void
    let onReject: () -> Void
    var onAnswer: ((String) -> Void)? = nil
    var onApproveAlways: (() -> Void)? = nil

    @State private var isHovered = false
    @State private var spinnerPhase = 0
    @State private var showDetail = false

    // Display settings
    @AppStorage("showActivityLog") private var showActivityLog = true
    @AppStorage("showConversation") private var showConversation = true
    @AppStorage("showTerminalBadge") private var showTerminalBadge = true
    @AppStorage("showTimeActive") private var showTimeActive = true
    @AppStorage("showAgentBadge") private var showAgentBadge = true

    private let claudeOrange = Color(red: 0.85, green: 0.47, blue: 0.34)
    private let spinnerSymbols = ["·", "✢", "✳", "∗", "✻", "✽"]
    private let spinnerTimer = Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()

    /// Terminal app name
    private var terminalName: String {
        if session.isInTmux { return "tmux" }
        return "cmux"
    }

    /// Vibe Island-style title: "project . session-summary"
    private var vibeIslandTitle: String {
        let project = session.projectName
        if let summary = session.summary {
            let cleaned = SessionState.cleanText(summary)
            if !cleaned.isEmpty && cleaned != project {
                return "\(project) · \(cleaned)"
            }
        }
        return project
    }

    /// Format time active as compact string (e.g., "4m", "1h 12m")
    private var timeActive: String? {
        guard let lastUserDate = session.lastUserMessageDate else { return nil }
        let elapsed = Date().timeIntervalSince(lastUserDate)
        if elapsed < 60 { return "<1m" }
        let minutes = Int(elapsed / 60)
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return "\(hours)h \(remainingMinutes)m"
    }

    /// Whether we're showing the approval UI
    private var isWaitingForApproval: Bool {
        session.phase.isWaitingForApproval
    }

    /// Whether the pending tool requires interactive input (not just approve/deny)
    private var isInteractiveTool: Bool {
        guard let toolName = session.pendingToolName else { return false }
        return toolName == "AskUserQuestion"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row: pixel icon + title + badges
            HStack(alignment: .center, spacing: 10) {
                SessionPixelIcon(sessionId: session.sessionId, phase: session.phase)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    // Title: "project . session-summary" like Vibe Island
                    Text(vibeIslandTitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    subtitleView
                }

                Spacer(minLength: 0)

                // Right side badges (respects display settings)
                HStack(spacing: 6) {
                    if showAgentBadge {
                        Text("Claude")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }

                    if showTerminalBadge {
                        Text(terminalName.lowercased())
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }

                    if showTimeActive, let time = timeActive {
                        Text(time)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.4))
                    }

                    // Jump to terminal button (visible on hover)
                    if isHovered {
                        Button { onFocus() } label: {
                            Image(systemName: "terminal")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white.opacity(0.6))
                                .frame(width: 22, height: 22)
                                .background(Color.white.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity)
                        .help("Jump to terminal")
                    }

                    // Archive button (visible on hover)
                    if isHovered {
                        Button { onArchive() } label: {
                            Image(systemName: "archivebox")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white.opacity(0.4))
                                .frame(width: 22, height: 22)
                                .background(Color.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity)
                    }
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .onTapGesture {
                onFocus()
            }

            // Expanded permission detail (inline diff, question buttons)
            if isWaitingForApproval, let permContext = session.activePermission {
                PermissionDetailView(
                    context: permContext,
                    onApprove: onApprove,
                    onDeny: onReject,
                    onAnswer: onAnswer,
                    onApproveAlways: onApproveAlways
                )
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Expanded view: conversation + activity (tap to toggle, respects settings)
            if showDetail && !isWaitingForApproval && !session.chatItems.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    if showConversation {
                        ConversationPreview(session: session)
                    }
                    if showActivityLog {
                        ActivityLogView(session: session)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isWaitingForApproval)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(rowBackground)
        )
        .onHover { isHovered = $0 }
    }

    /// Row background color based on state
    private var rowBackground: Color {
        if session.phase == .waitingForInput {
            // Green tint for "Done" state like Vibe Island
            return isHovered ? TerminalColors.green.opacity(0.12) : TerminalColors.green.opacity(0.06)
        }
        return isHovered ? Color.white.opacity(0.06) : Color.clear
    }

    // MARK: - Subtitle (matches Vibe Island: user msg gray + activity blue)

    /// Accent color for live activity text (green like Vibe Island)
    private let activityGreen = Color(red: 0.3, green: 0.8, blue: 0.4)

    @ViewBuilder
    private var subtitleView: some View {
        if isWaitingForApproval, let toolName = session.pendingToolName {
            // Permission request or Claude's Question
            if toolName == "AskUserQuestion" {
                HStack(spacing: 4) {
                    Text("🧡")
                        .font(.system(size: 10))
                    Text("Claude's Question")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(TerminalColors.amber.opacity(0.9))
                }
            } else {
                HStack(spacing: 4) {
                    Text(MCPToolFormatter.formatToolName(toolName))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(TerminalColors.amber.opacity(0.9))
                    Text("Needs approval")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
        } else if session.phase == .waitingForInput {
            // "Ready" state like Vibe Island (green text, click anywhere to jump)
            VStack(alignment: .leading, spacing: 2) {
                if let msg = session.lastMessage {
                    Text(msg)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                }
                Text("Ready")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(TerminalColors.green)
            }
        } else {
            // Active or idle: show both user msg + assistant msg like Vibe Island
            VStack(alignment: .leading, spacing: 2) {
                // User message in gray: "You: fix the auth bug"
                if let firstMsg = session.firstUserMessage {
                    Text("You: \(SessionState.cleanText(firstMsg))")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.45))
                        .lineLimit(1)
                }
                // Assistant response or current tool activity
                if session.phase == .processing || session.phase == .compacting {
                    // Active: show current tool in green (like Vibe Island)
                    if let toolName = session.lastToolName, let toolInput = session.lastMessage {
                        Text("\(MCPToolFormatter.formatToolName(toolName)) \(toolInput)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(activityGreen)
                            .lineLimit(1)
                    }
                } else if let msg = session.lastMessage {
                    // Idle: show last assistant message
                    Text(msg)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }
        }
    }

    // Action buttons removed — badges (Claude, cmux, time, ^G ↗) are now
    // inline in the title row. Permission UI is in PermissionDetailView below.

    @ViewBuilder
    private var stateIndicator: some View {
        switch session.phase {
        case .processing, .compacting:
            Text(spinnerSymbols[spinnerPhase % spinnerSymbols.count])
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(claudeOrange)
                .onReceive(spinnerTimer) { _ in
                    spinnerPhase = (spinnerPhase + 1) % spinnerSymbols.count
                }
        case .waitingForApproval:
            Text(spinnerSymbols[spinnerPhase % spinnerSymbols.count])
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(TerminalColors.amber)
                .onReceive(spinnerTimer) { _ in
                    spinnerPhase = (spinnerPhase + 1) % spinnerSymbols.count
                }
        case .waitingForInput:
            Circle()
                .fill(TerminalColors.green)
                .frame(width: 6, height: 6)
        case .idle, .ended:
            Circle()
                .fill(Color.white.opacity(0.2))
                .frame(width: 6, height: 6)
        }
    }

}

// MARK: - Project Group Header

struct ProjectGroupHeader: View {
    let project: String
    let count: Int

    var body: some View {
        HStack {
            Text("\(project) (\(count))")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

// MARK: - Session Pixel Icon (unique colored icon per session like Vibe Island)

struct SessionPixelIcon: View {
    let sessionId: String
    let phase: SessionPhase

    /// Generate two colors from session ID hash for a unique pixel pattern
    private var colors: (Color, Color) {
        let hash = abs(sessionId.hashValue)
        let hue1 = Double(hash % 360) / 360.0
        let hue2 = Double((hash / 360) % 360) / 360.0
        return (
            Color(hue: hue1, saturation: 0.7, brightness: 0.8),
            Color(hue: hue2, saturation: 0.6, brightness: 0.7)
        )
    }

    /// Generate a 4x4 pixel pattern from session ID
    private var pattern: [[Bool]] {
        let hash = abs(sessionId.hashValue)
        var grid: [[Bool]] = []
        for row in 0..<4 {
            var line: [Bool] = []
            for col in 0..<2 {
                // Use bits from hash to determine pixel state
                let bit = (hash >> (row * 2 + col)) & 1
                line.append(bit == 1)
            }
            // Mirror for symmetry
            line.append(contentsOf: line.reversed())
            grid.append(line)
        }
        return grid
    }

    var body: some View {
        let (color1, color2) = colors
        let grid = pattern

        VStack(spacing: 1) {
            ForEach(0..<4, id: \.self) { row in
                HStack(spacing: 1) {
                    ForEach(0..<4, id: \.self) { col in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(grid[row][col] ? color1 : color2.opacity(0.3))
                            .frame(width: 5, height: 5)
                    }
                }
            }
        }
        .opacity(phase == .idle || phase == .ended ? 0.5 : 1.0)
    }
}

// MARK: - Conversation Preview (Vibe Island-style chat in expanded card)

struct ConversationPreview: View {
    let session: SessionState

    /// Extract recent user + assistant messages
    private var recentMessages: [(id: String, role: String, text: String)] {
        var messages: [(id: String, role: String, text: String)] = []
        for item in session.chatItems.suffix(20) {
            switch item.type {
            case .user(let text):
                let cleaned = SessionState.cleanText(text)
                if !cleaned.isEmpty && cleaned.count > 5 {
                    messages.append((id: item.id, role: "user", text: cleaned))
                }
            case .assistant(let text):
                let cleaned = SessionState.cleanText(text)
                if !cleaned.isEmpty && cleaned.count > 5 {
                    messages.append((id: item.id, role: "assistant", text: cleaned))
                }
            default:
                break
            }
        }
        return Array(messages.suffix(4)) // Last 4 messages
    }

    var body: some View {
        if recentMessages.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(recentMessages, id: \.id) { msg in
                    HStack(alignment: .top, spacing: 6) {
                        if msg.role == "user" {
                            Text("You:")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.5))
                            Text(msg.text)
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.5))
                                .lineLimit(2)
                        } else {
                            Text(msg.text)
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.75))
                                .lineLimit(3)
                        }
                        Spacer(minLength: 0)
                        if msg.role == "assistant" {
                            Text("Done")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white.opacity(0.3))
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(msg.role == "user" ? Color.white.opacity(0.04) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }
}

// MARK: - Inline Approval Buttons

/// Compact inline approval buttons with staggered animation
struct InlineApprovalButtons: View {
    let onChat: () -> Void
    let onApprove: () -> Void
    let onReject: () -> Void

    @State private var showChatButton = false
    @State private var showDenyButton = false
    @State private var showAllowButton = false

    var body: some View {
        HStack(spacing: 6) {
            // Chat button
            IconButton(icon: "bubble.left") {
                onChat()
            }
            .opacity(showChatButton ? 1 : 0)
            .scaleEffect(showChatButton ? 1 : 0.8)

            Button {
                onReject()
            } label: {
                Text("Deny")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .opacity(showDenyButton ? 1 : 0)
            .scaleEffect(showDenyButton ? 1 : 0.8)

            Button {
                onApprove()
            } label: {
                Text("Allow")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.9))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .opacity(showAllowButton ? 1 : 0)
            .scaleEffect(showAllowButton ? 1 : 0.8)
        }
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.0)) {
                showChatButton = true
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.05)) {
                showDenyButton = true
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.1)) {
                showAllowButton = true
            }
        }
    }
}

// MARK: - Icon Button

struct IconButton: View {
    let icon: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button {
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isHovered ? .white.opacity(0.8) : .white.opacity(0.4))
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered ? Color.white.opacity(0.1) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Compact Terminal Button (inline in description)

struct CompactTerminalButton: View {
    let isEnabled: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            if isEnabled {
                onTap()
            }
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "terminal")
                    .font(.system(size: 8, weight: .medium))
                Text("Go to Terminal")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(isEnabled ? .white.opacity(0.9) : .white.opacity(0.3))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(isEnabled ? Color.white.opacity(0.15) : Color.white.opacity(0.05))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Terminal Button

struct TerminalButton: View {
    let isEnabled: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            if isEnabled {
                onTap()
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "terminal")
                    .font(.system(size: 9, weight: .medium))
                Text("Terminal")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(isEnabled ? .black : .white.opacity(0.4))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isEnabled ? Color.white.opacity(0.95) : Color.white.opacity(0.1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
