//
//  NotchView.swift
//  ClaudePerch
//
//  The main dynamic island SwiftUI view with accurate notch shape
//

import AppKit
import Combine
import CoreGraphics
import SwiftUI

// Corner radius constants
private let cornerRadiusInsets = (
    opened: (top: CGFloat(19), bottom: CGFloat(24)),
    closed: (top: CGFloat(6), bottom: CGFloat(14))
)

struct NotchView: View {
    @ObservedObject var viewModel: NotchViewModel
    @StateObject private var sessionMonitor = ClaudeSessionMonitor()
    @StateObject private var activityCoordinator = NotchActivityCoordinator.shared
    @ObservedObject private var updateManager = UpdateManager.shared
    @ObservedObject private var usageProvider = UsageStatsProvider.shared
    @State private var previousPendingIds: Set<String> = []
    @State private var previousWaitingForInputIds: Set<String> = []
    @State private var waitingForInputTimestamps: [String: Date] = [:]  // sessionId -> when it entered waitingForInput
    @State private var isVisible: Bool = false
    @State private var isHovering: Bool = false
    @State private var isBouncing: Bool = false

    // Settings (wired to SettingsWindow toggles)
    @AppStorage("hideInFullscreen") private var hideInFullscreen = true
    @AppStorage("autoHideNoSessions") private var autoHideNoSessions = false
    @AppStorage("smartSuppression") private var smartSuppression = true
    @AppStorage("autoCollapse") private var autoCollapse = true
    @AppStorage("soundEnabled") private var soundEnabled = true
    @AppStorage("soundVolume") private var soundVolume = 0.3
    @AppStorage("soundSessionStart") private var soundSessionStart = true
    @AppStorage("soundTaskComplete") private var soundTaskComplete = true
    @AppStorage("soundApprovalNeeded") private var soundApprovalNeeded = true
    @AppStorage("showUsage") private var showUsageSetting = true

    @Namespace private var activityNamespace

    /// Whether any Claude session is currently processing or compacting
    private var isAnyProcessing: Bool {
        sessionMonitor.instances.contains { $0.phase == .processing || $0.phase == .compacting }
    }

    /// Whether any Claude session has a pending permission request
    private var hasPendingPermission: Bool {
        sessionMonitor.instances.contains { $0.phase.isWaitingForApproval }
    }

    /// Whether any Claude session is waiting for user input (done/ready state) within the display window
    private var hasWaitingForInput: Bool {
        let now = Date()
        let displayDuration: TimeInterval = 30  // Show checkmark for 30 seconds

        return sessionMonitor.instances.contains { session in
            guard session.phase == .waitingForInput else { return false }
            // Only show if within the 30-second display window
            if let enteredAt = waitingForInputTimestamps[session.stableId] {
                return now.timeIntervalSince(enteredAt) < displayDuration
            }
            return false
        }
    }

    // MARK: - Sizing

    private var closedNotchSize: CGSize {
        CGSize(
            width: viewModel.deviceNotchRect.width,
            height: viewModel.deviceNotchRect.height
        )
    }

    /// Extra width for expanding activities (like Dynamic Island)
    private var expansionWidth: CGFloat {
        // Permission indicator adds width on left side only
        let permissionIndicatorWidth: CGFloat = hasPendingPermission ? 18 : 0

        // Expand for processing activity
        if activityCoordinator.expandingActivity.show {
            switch activityCoordinator.expandingActivity.type {
            case .claude:
                let baseWidth = 2 * max(0, closedNotchSize.height - 12) + 20
                return baseWidth + permissionIndicatorWidth
            case .none:
                break
            }
        }

        // Expand for pending permissions (left indicator) or waiting for input (checkmark on right)
        if hasPendingPermission {
            return 2 * max(0, closedNotchSize.height - 12) + 20 + permissionIndicatorWidth
        }

        // Waiting for input just shows checkmark on right, no extra left indicator
        if hasWaitingForInput {
            return 2 * max(0, closedNotchSize.height - 12) + 20
        }

        return 0
    }

    private var notchSize: CGSize {
        switch viewModel.status {
        case .closed, .popping:
            return closedNotchSize
        case .opened:
            return viewModel.openedSize
        }
    }

    /// Width of the closed content (notch + any expansion)
    private var closedContentWidth: CGFloat {
        closedNotchSize.width + expansionWidth
    }

    // MARK: - Corner Radii

    private var topCornerRadius: CGFloat {
        viewModel.status == .opened
            ? cornerRadiusInsets.opened.top
            : cornerRadiusInsets.closed.top
    }

    private var bottomCornerRadius: CGFloat {
        viewModel.status == .opened
            ? cornerRadiusInsets.opened.bottom
            : cornerRadiusInsets.closed.bottom
    }

    private var currentNotchShape: NotchShape {
        NotchShape(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: bottomCornerRadius
        )
    }

    // Animation springs
    private let openAnimation = Animation.spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
    private let closeAnimation = Animation.spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            // Outer container does NOT receive hits - only the notch content does
            VStack(spacing: 0) {
                notchLayout
                    .frame(
                        maxWidth: viewModel.status == .opened ? notchSize.width : nil,
                        alignment: .top
                    )
                    .padding(
                        .horizontal,
                        viewModel.status == .opened
                            ? cornerRadiusInsets.opened.top
                            : cornerRadiusInsets.closed.bottom
                    )
                    .padding([.horizontal, .bottom], viewModel.status == .opened ? 12 : 0)
                    .background(.black)
                    .clipShape(currentNotchShape)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(.black)
                            .frame(height: 1)
                            .padding(.horizontal, topCornerRadius)
                    }
                    .shadow(
                        color: (viewModel.status == .opened || isHovering) ? .black.opacity(0.7) : .clear,
                        radius: 6
                    )
                    .frame(
                        maxWidth: viewModel.status == .opened ? notchSize.width : nil,
                        maxHeight: viewModel.status == .opened ? notchSize.height : nil,
                        alignment: .top
                    )
                    .animation(viewModel.status == .opened ? openAnimation : closeAnimation, value: viewModel.status)
                    .animation(openAnimation, value: notchSize) // Animate container size changes between content types
                    .animation(.smooth, value: activityCoordinator.expandingActivity)
                    .animation(.smooth, value: hasPendingPermission)
                    .animation(.smooth, value: hasWaitingForInput)
                    .animation(.spring(response: 0.3, dampingFraction: 0.5), value: isBouncing)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
                            isHovering = hovering
                        }
                    }
                    .onTapGesture {
                        if viewModel.status != .opened {
                            viewModel.notchOpen(reason: .click)
                        }
                    }
            }
        }
        .opacity(isVisible ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark)
        .onAppear {
            sessionMonitor.startMonitoring()
            startGlobalHotkeys()
            // On non-notched devices, keep visible so users have a target to interact with
            if !viewModel.hasPhysicalNotch {
                isVisible = true
            }
        }
        .onChange(of: viewModel.status) { oldStatus, newStatus in
            handleStatusChange(from: oldStatus, to: newStatus)
        }
        .onChange(of: sessionMonitor.pendingInstances) { _, sessions in
            handlePendingSessionsChange(sessions)
        }
        .onChange(of: sessionMonitor.instances) { _, instances in
            handleProcessingChange()
            handleWaitingForInputChange(instances)
        }
    }

    // MARK: - Notch Layout

    private var isProcessing: Bool {
        activityCoordinator.expandingActivity.show && activityCoordinator.expandingActivity.type == .claude
    }

    /// Whether to show the expanded closed state (processing, pending permission, or waiting for input)
    private var showClosedActivity: Bool {
        isProcessing || hasPendingPermission || hasWaitingForInput
    }

    @ViewBuilder
    private var notchLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Closed with sessions: show Vibe Island-style status strip instead of crab
            if viewModel.status != .opened && !sessionMonitor.instances.isEmpty {
                statusStrip
                    .frame(height: max(24, closedNotchSize.height))
            } else {
                // Header row: crab + spinner (when opened or no sessions)
                headerRow
                    .frame(height: max(24, closedNotchSize.height))
            }

            // Usage stats bar (controlled by "Show Usage" setting)
            if viewModel.status == .opened && !sessionMonitor.instances.isEmpty && showUsageSetting {
                usageStatsBar
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
            }

            // Main content only when opened
            if viewModel.status == .opened {
                contentView
                    .frame(width: notchSize.width - 24) // Fixed width to prevent reflow
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.8, anchor: .top)
                                .combined(with: .opacity)
                                .animation(.smooth(duration: 0.35)),
                            removal: .opacity.animation(.easeOut(duration: 0.15))
                        )
                    )
            }
        }
    }

    // MARK: - Status Strip (Vibe Island style: icon + activity + count)

    @ViewBuilder
    private var statusStrip: some View {
        let sessions = sessionMonitor.instances
        // Find the most active session to show in the strip
        let activeSession = sessions.first(where: { $0.phase == .processing || $0.phase == .compacting })
            ?? sessions.first(where: { $0.phase.isWaitingForApproval })
            ?? sessions.first(where: { $0.phase == .waitingForInput })
            ?? sessions.first

        if let session = activeSession {
            HStack(spacing: 6) {
                // Mini pixel icon
                SessionPixelIcon(sessionId: session.sessionId, phase: session.phase)
                    .frame(width: 16, height: 16)
                    .scaleEffect(0.7)

                // Current activity text
                if let toolName = session.lastToolName, let input = session.lastMessage {
                    Text("\(MCPToolFormatter.formatToolName(toolName)): \(input)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                } else if session.phase == .waitingForInput {
                    Text("Ready")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(TerminalColors.green)
                } else if session.phase.isWaitingForApproval {
                    Text("Approval needed")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(TerminalColors.amber)
                }

                // Session count
                if sessions.count > 0 {
                    Text("\(sessions.count) session\(sessions.count == 1 ? "" : "s")")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.35))
                }
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Header Row (persists across states)

    @ViewBuilder
    private var headerRow: some View {
        HStack(spacing: 0) {
            // Left side - crab + optional permission indicator (visible when processing, pending, or waiting for input)
            if showClosedActivity {
                HStack(spacing: 4) {
                    ClaudeCrabIcon(size: 14, animateLegs: isProcessing)
                        .matchedGeometryEffect(id: "crab", in: activityNamespace, isSource: showClosedActivity)

                    // Permission indicator only (amber) - waiting for input shows checkmark on right
                    if hasPendingPermission {
                        PermissionIndicatorIcon(size: 14, color: Color(red: 0.85, green: 0.47, blue: 0.34))
                            .matchedGeometryEffect(id: "status-indicator", in: activityNamespace, isSource: showClosedActivity)
                    }
                }
                .frame(width: viewModel.status == .opened ? nil : sideWidth + (hasPendingPermission ? 18 : 0))
                .padding(.leading, viewModel.status == .opened ? 8 : 0)
            }

            // Center content
            if viewModel.status == .opened {
                // Opened: show header content
                openedHeaderContent
            } else if !showClosedActivity {
                // Closed without activity: empty space
                Rectangle()
                    .fill(.clear)
                    .frame(width: closedNotchSize.width - 20)
            } else {
                // Closed with activity: black spacer (with optional bounce)
                Rectangle()
                    .fill(.black)
                    .frame(width: closedNotchSize.width - cornerRadiusInsets.closed.top + (isBouncing ? 16 : 0))
            }

            // Right side - spinner when processing/pending, checkmark when waiting for input
            if showClosedActivity {
                if isProcessing || hasPendingPermission {
                    ProcessingSpinner()
                        .matchedGeometryEffect(id: "spinner", in: activityNamespace, isSource: showClosedActivity)
                        .frame(width: viewModel.status == .opened ? 20 : sideWidth)
                } else if hasWaitingForInput {
                    // Checkmark for waiting-for-input on the right side
                    ReadyForInputIndicatorIcon(size: 14, color: TerminalColors.green)
                        .matchedGeometryEffect(id: "spinner", in: activityNamespace, isSource: showClosedActivity)
                        .frame(width: viewModel.status == .opened ? 20 : sideWidth)
                }
            }
        }
        .frame(height: closedNotchSize.height)
    }

    private var sideWidth: CGFloat {
        max(0, closedNotchSize.height - 12) + 10
    }

    // MARK: - Opened Header Content

    @ViewBuilder
    private var openedHeaderContent: some View {
        HStack(spacing: 12) {
            // Show static crab only if not showing activity in headerRow
            // (headerRow handles crab + indicator when showClosedActivity is true)
            if !showClosedActivity {
                ClaudeCrabIcon(size: 14)
                    .matchedGeometryEffect(id: "crab", in: activityNamespace, isSource: !showClosedActivity)
                    .padding(.leading, 8)
            }

            Spacer()

            // Sound mute toggle (like Vibe Island)
            Button {
                soundEnabled.toggle()
            } label: {
                Image(systemName: soundEnabled ? "speaker.wave.2" : "speaker.slash")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Settings gear (opens separate window like Vibe Island)
            Button {
                SettingsWindowController.shared.showSettings()
            } label: {
                Image(systemName: "gear")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Content View (Opened State)

    @ViewBuilder
    private var contentView: some View {
        Group {
            switch viewModel.contentType {
            case .instances:
                ClaudeInstancesView(
                    sessionMonitor: sessionMonitor,
                    viewModel: viewModel
                )
            case .menu:
                // Menu replaced by settings window (gear icon)
                ClaudeInstancesView(
                    sessionMonitor: sessionMonitor,
                    viewModel: viewModel
                )
            case .chat(let session):
                ChatView(
                    sessionId: session.sessionId,
                    initialSession: session,
                    sessionMonitor: sessionMonitor,
                    viewModel: viewModel
                )
            }
        }
        .frame(width: notchSize.width - 24) // Fixed width to prevent text reflow
        // Removed .id() - was causing view recreation and performance issues
    }

    // MARK: - Event Handlers

    private func handleProcessingChange() {
        if isAnyProcessing || hasPendingPermission {
            // Show claude activity when processing or waiting for permission
            activityCoordinator.showActivity(type: .claude)
            isVisible = true
        } else if hasWaitingForInput {
            // Keep visible for waiting-for-input but hide the processing spinner
            activityCoordinator.hideActivity()
            isVisible = true
        } else {
            // Hide activity when done
            activityCoordinator.hideActivity()

            // Delay hiding the notch until animation completes
            // Don't hide on non-notched devices - users need a visible target
            if viewModel.status == .closed && viewModel.hasPhysicalNotch {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if !isAnyProcessing && !hasPendingPermission && !hasWaitingForInput && viewModel.status == .closed {
                        isVisible = false
                    }
                }
            }
        }
    }

    private func handleStatusChange(from oldStatus: NotchStatus, to newStatus: NotchStatus) {
        switch newStatus {
        case .opened, .popping:
            isVisible = true
            // Clear waiting-for-input timestamps only when manually opened (user acknowledged)
            if viewModel.openReason == .click || viewModel.openReason == .hover {
                waitingForInputTimestamps.removeAll()
            }
        case .closed:
            // Don't hide on non-notched devices - users need a visible target
            guard viewModel.hasPhysicalNotch else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                let noActivity = !isAnyProcessing && !hasPendingPermission && !hasWaitingForInput && !activityCoordinator.expandingActivity.show
                let noSessions = sessionMonitor.instances.isEmpty
                if viewModel.status == .closed && (noActivity || (autoHideNoSessions && noSessions)) {
                    isVisible = false
                }
            }
        }
    }

    private func handlePendingSessionsChange(_ sessions: [SessionState]) {
        let currentIds = Set(sessions.map { $0.stableId })
        let newPendingIds = currentIds.subtracting(previousPendingIds)

        if !newPendingIds.isEmpty {
            // Play urgent notification sound for new permission requests
            if soundEnabled && soundApprovalNeeded,
               let soundName = AppSettings.urgentNotificationSound.soundName {
                let newSessions = sessions.filter { newPendingIds.contains($0.stableId) }
                let volume = soundVolume
                Task {
                    let shouldPlay = await shouldPlayNotificationSound(for: newSessions)
                    if shouldPlay {
                        await MainActor.run {
                            if let sound = NSSound(named: soundName) {
                                sound.volume = Float(volume)
                                sound.play()
                            }
                        }
                    }
                }
            }

            // ALWAYS pop the notch open for permission requests (they need user action)
            // Smart suppression does NOT apply to permissions - they're urgent
            if viewModel.status == .closed {
                viewModel.notchOpen(reason: .notification)
            }
        }

        previousPendingIds = currentIds
    }

    private func handleWaitingForInputChange(_ instances: [SessionState]) {
        // Get sessions that are now waiting for input
        let waitingForInputSessions = instances.filter { $0.phase == .waitingForInput }
        let currentIds = Set(waitingForInputSessions.map { $0.stableId })
        let newWaitingIds = currentIds.subtracting(previousWaitingForInputIds)

        // Track timestamps for newly waiting sessions
        let now = Date()
        for session in waitingForInputSessions where newWaitingIds.contains(session.stableId) {
            waitingForInputTimestamps[session.stableId] = now
        }

        // Clean up timestamps for sessions no longer waiting
        let staleIds = Set(waitingForInputTimestamps.keys).subtracting(currentIds)
        for staleId in staleIds {
            waitingForInputTimestamps.removeValue(forKey: staleId)
        }

        // Bounce the notch when a session newly enters waitingForInput state
        if !newWaitingIds.isEmpty {
            // Get the sessions that just entered waitingForInput
            let newlyWaitingSessions = waitingForInputSessions.filter { newWaitingIds.contains($0.stableId) }

            // Play task complete sound (respects settings)
            if soundEnabled && soundTaskComplete,
               let soundName = AppSettings.notificationSound.soundName {
                let volume = soundVolume
                Task {
                    let shouldPlaySound = await shouldPlayNotificationSound(for: newlyWaitingSessions)
                    if shouldPlaySound {
                        await MainActor.run {
                            if let sound = NSSound(named: soundName) {
                                sound.volume = Float(volume)
                                sound.play()
                            }
                        }
                    }
                }
            }

            // Don't pop open for "Ready" state - just update the closed notch bar
            // Only permission requests should auto-pop (handled in handlePendingSessionsChange)

            // Trigger bounce animation to get user's attention
            DispatchQueue.main.async {
                isBouncing = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    isBouncing = false
                }
            }

            // Schedule hiding the checkmark after 30 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [self] in
                // Trigger a UI update to re-evaluate hasWaitingForInput
                handleProcessingChange()
            }
        }

        previousWaitingForInputIds = currentIds
    }

    // MARK: - Usage Stats Bar (like Vibe Island top bar)

    /// Format remaining time until reset as "Xh XXm"
    private func formatResetTime(_ date: Date) -> String {
        let remaining = date.timeIntervalSinceNow
        if remaining <= 0 { return "now" }
        let totalMinutes = Int(remaining / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours)h \(String(format: "%02d", minutes))m"
        }
        return "\(minutes)m"
    }

    @ViewBuilder
    private var usageStatsBar: some View {
        let totalSessions = sessionMonitor.instances.count
        let activeSessions = sessionMonitor.instances.filter { $0.phase == .processing || $0.phase == .compacting }.count

        HStack(spacing: 4) {
            // Status indicator
            Circle()
                .fill(activeSessions > 0 ? Color.orange : TerminalColors.green)
                .frame(width: 8, height: 8)

            // Format: "5h X% | resets in Xh XXm"
            if let usage = usageProvider.stats {
                Text("5h")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.7))
                Text("\(Int(usage.fiveHourPercent))%")
                    .font(.system(size: 10))
                    .foregroundColor(usage.fiveHourPercent > 80 ? Color.red.opacity(0.9) : .white.opacity(0.4))

                Text("|")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.2))

                // Show reset time based on 7d window
                if let reset = usage.sevenDayResetsAt {
                    Text("resets in")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.3))
                    Text(formatResetTime(reset))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                }
            } else {
                // Fallback: show session time when no usage data
                if let oldest = sessionMonitor.instances.min(by: { $0.createdAt < $1.createdAt }) {
                    let elapsed = Date().timeIntervalSince(oldest.createdAt)
                    let hours = Int(elapsed / 3600)
                    let minutes = Int(elapsed.truncatingRemainder(dividingBy: 3600) / 60)
                    Text("\(hours)h")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.7))
                    Text("\(String(format: "%02d", minutes))m")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                }
            }

            Text("|")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.2))

            // Total sessions info
            Text("\(totalSessions) session\(totalSessions == 1 ? "" : "s")")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.4))

            Spacer()
        }
        .onAppear {
            usageProvider.refresh()
        }
        .onReceive(Timer.publish(every: 300, on: .main, in: .common).autoconnect()) { _ in
            usageProvider.refresh()
        }
    }

    /// Check if a fullscreen app is active on the current screen
    private var isFullscreenAppActive: Bool {
        guard hideInFullscreen else { return false }
        // Check if the frontmost app is in fullscreen
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            for window in NSApplication.shared.windows {
                if window.styleMask.contains(.fullScreen) {
                    return true
                }
            }
        }
        // Check via screen's visible frame vs frame
        if let screen = NSScreen.main {
            return screen.visibleFrame.height == screen.frame.height
        }
        return false
    }

    /// Determine if notification sound should play for the given sessions
    /// Returns true if ANY session is not actively focused
    private func shouldPlayNotificationSound(for sessions: [SessionState]) async -> Bool {
        for session in sessions {
            guard let pid = session.pid else {
                // No PID means we can't check focus, assume not focused
                return true
            }

            let isFocused = await TerminalVisibilityDetector.isSessionFocused(sessionPid: pid)
            if !isFocused {
                return true
            }
        }

        return false
    }

    // MARK: - Global Hotkeys

    private func startGlobalHotkeys() {
        let manager = GlobalHotkeyManager.shared

        // ^G - Toggle panel open/close
        let vm = viewModel
        manager.onTogglePanel = {
            if vm.status == .opened {
                vm.notchClose()
            } else {
                vm.notchOpen(reason: .click)
            }
        }

        // ^Y - Approve
        manager.onApprove = { [weak sessionMonitor] in
            guard let monitor = sessionMonitor else { return }
            if let session = monitor.instances.first(where: { $0.phase.isWaitingForApproval }) {
                monitor.approvePermission(sessionId: session.sessionId)
            }
        }

        // ^N - Deny
        manager.onDeny = { [weak sessionMonitor] in
            guard let monitor = sessionMonitor else { return }
            if let session = monitor.instances.first(where: { $0.phase.isWaitingForApproval }) {
                monitor.denyPermission(sessionId: session.sessionId, reason: nil)
            }
        }

        // ^A - Always Allow (same as approve for now)
        manager.onAlwaysAllow = { [weak sessionMonitor] in
            guard let monitor = sessionMonitor else { return }
            if let session = monitor.instances.first(where: { $0.phase.isWaitingForApproval }) {
                monitor.approvePermission(sessionId: session.sessionId)
            }
        }

        // ^B - Bypass Permissions (same as approve for now)
        manager.onBypass = { [weak sessionMonitor] in
            guard let monitor = sessionMonitor else { return }
            if let session = monitor.instances.first(where: { $0.phase.isWaitingForApproval }) {
                monitor.approvePermission(sessionId: session.sessionId)
            }
        }

        // ^T - Jump to Terminal (most active session)
        manager.onJumpToTerminal = { [weak sessionMonitor] in
            guard let monitor = sessionMonitor else { return }
            let active = monitor.instances.first(where: { $0.phase.isWaitingForApproval })
                ?? monitor.instances.first(where: { $0.phase == .waitingForInput })
                ?? monitor.instances.first(where: { $0.phase == .processing })
                ?? monitor.instances.first
            if let session = active {
                Task {
                    _ = await AppFocusManager.shared.focusSession(
                        pid: session.pid, cwd: session.cwd, isInTmux: session.isInTmux,
                        sessionTitle: session.displayTitle, sessionId: session.sessionId,
                        sessionSummary: session.summary
                    )
                }
            }
        }

        // ^1-9 - Select question option
        manager.onSelectOption = { [weak sessionMonitor] index in
            guard let monitor = sessionMonitor else { return }
            if let session = monitor.instances.first(where: {
                $0.phase.isWaitingForApproval && $0.pendingToolName == "AskUserQuestion"
            }) {
                // Extract the option label at the given index
                if let input = session.activePermission?.toolInput,
                   let questions = input["questions"]?.value as? [[String: Any]],
                   let first = questions.first,
                   let options = first["options"] as? [[String: Any]],
                   index < options.count,
                   let label = options[index]["label"] as? String {
                    monitor.answerQuestion(sessionId: session.sessionId, selectedOption: label)
                }
            }
        }

        manager.start()
    }
}
