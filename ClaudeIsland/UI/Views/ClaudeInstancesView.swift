//
//  ClaudeInstancesView.swift
//  ClaudeIsland
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
                            onReject: { rejectSession(session) }
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
                sessionTitle: session.displayTitle
            )
        }
    }

    private func openChat(_ session: SessionState) {
        viewModel.showChat(for: session)
    }

    private func approveSession(_ session: SessionState) {
        sessionMonitor.approvePermission(sessionId: session.sessionId)
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

    @State private var isHovered = false
    @State private var spinnerPhase = 0
    @State private var showDetail = false

    private let claudeOrange = Color(red: 0.85, green: 0.47, blue: 0.34)
    private let spinnerSymbols = ["·", "✢", "✳", "∗", "✻", "✽"]
    private let spinnerTimer = Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()

    /// Terminal app name based on TTY (displayed like Vibe Island "Claude iTerm 7m")
    private var terminalName: String {
        if session.isInTmux { return "tmux" }
        // Default to Ghostty since the user uses cmux/Ghostty
        return "Ghostty"
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
            // Main row: status dot + title + actions
            HStack(alignment: .center, spacing: 10) {
                stateIndicator
                    .frame(width: 14)

                VStack(alignment: .leading, spacing: 2) {
                    // Title row: session name + terminal + time (like Vibe Island)
                    HStack(spacing: 6) {
                        Text(session.displayTitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        Text(terminalName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.3))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }

                    subtitleView
                }

                Spacer(minLength: 0)

                actionButtons
            }
            .padding(.leading, 8)
            .padding(.trailing, 14)
            .padding(.vertical, 10)

            // Expanded permission detail (inline diff, question buttons)
            if isWaitingForApproval, let permContext = session.activePermission {
                PermissionDetailView(
                    context: permContext,
                    onApprove: onApprove,
                    onDeny: onReject,
                    onAnswer: onAnswer
                )
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Activity log - always visible when session has tool history
            if !isWaitingForApproval && !session.chatItems.isEmpty {
                ActivityLogView(session: session)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onChat()
        }
        .onTapGesture(count: 1) {
            if session.phase == .waitingForInput {
                // "Done" state: tap anywhere to jump to terminal
                onFocus()
            } else {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showDetail.toggle()
                }
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

    /// Accent color for live activity text (blue like Vibe Island)
    private let activityBlue = Color(red: 0.4, green: 0.6, blue: 1.0)

    @ViewBuilder
    private var subtitleView: some View {
        if isWaitingForApproval, let toolName = session.pendingToolName {
            // Permission request
            HStack(spacing: 4) {
                Text(MCPToolFormatter.formatToolName(toolName))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(TerminalColors.amber.opacity(0.9))
                Text("Needs approval")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
        } else if session.phase == .waitingForInput {
            // Done state: last message + "Done click to jump"
            VStack(alignment: .leading, spacing: 3) {
                if let msg = session.lastMessage {
                    Text(msg)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                }
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(TerminalColors.green)
                    Text("Done")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(TerminalColors.green)
                    Text("click to jump")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
        } else if session.phase == .processing || session.phase == .compacting {
            // Active processing: show "You: message" + current tool in blue
            VStack(alignment: .leading, spacing: 2) {
                // Last user message in gray (like "You: fix the auth bug")
                if let firstMsg = session.firstUserMessage {
                    Text("You: \(SessionState.cleanText(firstMsg))")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.45))
                        .lineLimit(1)
                }
                // Current tool activity in blue (like "Writing middleware.ts")
                if let toolName = session.lastToolName, let toolInput = session.lastMessage {
                    Text("\(MCPToolFormatter.formatToolName(toolName)) \(toolInput)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(activityBlue)
                        .lineLimit(1)
                } else if let msg = session.lastMessage {
                    Text(msg)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(activityBlue)
                        .lineLimit(1)
                }
            }
        } else {
            // Idle: just show last message
            if let msg = session.lastMessage {
                Text(msg)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        if isWaitingForApproval {
            // Approval actions are in the expanded PermissionDetailView below
            HStack(spacing: 8) {
                IconButton(icon: "bubble.left") { onChat() }
                IconButton(icon: "eye") { onFocus() }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        } else if session.phase == .waitingForInput {
            // "Done" state: prominent jump button
            HStack(spacing: 8) {
                if let time = timeActive {
                    Text(time)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                }
                TerminalButton(isEnabled: true, onTap: { onFocus() })
                IconButton(icon: "archivebox") { onArchive() }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        } else {
            HStack(spacing: 8) {
                if let time = timeActive {
                    Text(time)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                }
                IconButton(icon: "bubble.left") { onChat() }
                IconButton(icon: "eye") { onFocus() }
                if session.phase == .idle {
                    IconButton(icon: "archivebox") { onArchive() }
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }

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
