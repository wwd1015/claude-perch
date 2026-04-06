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
    @StateObject var sessionMonitor = ClaudeSessionMonitor()
    @StateObject var activityCoordinator = NotchActivityCoordinator.shared
    @StateObject var completionQueue = CompletionQueue()
    @ObservedObject private var updateManager = UpdateManager.shared
    @ObservedObject var usageProvider = UsageStatsProvider.shared
    @State var previousPendingIds: Set<String> = []
    @State var previousWaitingForInputIds: Set<String> = []
    @State var isVisible: Bool = false
    @State private var isHovering: Bool = false
    @State var isBouncing: Bool = false

    // Settings (wired to SettingsWindow toggles)
    @AppStorage("hideInFullscreen") private var hideInFullscreen = true
    @AppStorage("autoHideNoSessions") var autoHideNoSessions = false
    @AppStorage("smartSuppression") private var smartSuppression = true
    @AppStorage("autoCollapse") private var autoCollapse = true
    @AppStorage("soundEnabled") var soundEnabled = true
    @AppStorage("soundVolume") var soundVolume = 0.3
    @AppStorage("soundSessionStart") private var soundSessionStart = true
    @AppStorage("soundTaskComplete") var soundTaskComplete = true
    @AppStorage("soundApprovalNeeded") var soundApprovalNeeded = true
    @AppStorage("showUsage") private var showUsageSetting = true

    @Namespace private var activityNamespace

    /// Whether any Claude session is currently processing or compacting
    var isAnyProcessing: Bool {
        sessionMonitor.instances.contains { $0.phase == .processing || $0.phase == .compacting }
    }

    /// Whether any Claude session has a pending permission request
    var hasPendingPermission: Bool {
        sessionMonitor.instances.contains { $0.phase.isWaitingForApproval }
    }

    /// Whether any Claude session is waiting for user input (done/ready state)
    var hasWaitingForInput: Bool {
        completionQueue.isShowing
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

        // Waiting for input: wider expansion for prominent "Done" display
        if hasWaitingForInput {
            return 2 * max(0, closedNotchSize.height - 12) + 80
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
                        if hasWaitingForInput {
                            completionQueue.setHovering(hovering)
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
                UsageStatsBar(usageProvider: usageProvider, sessionMonitor: sessionMonitor)
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
            } else if hasWaitingForInput && !isProcessing && !hasPendingPermission {
                // Closed with Done state: show prominent checkmark + "Done" text
                HStack(spacing: 6) {
                    Rectangle().fill(.black)
                        .frame(width: closedNotchSize.width - cornerRadiusInsets.closed.top)

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(TerminalColors.green)

                    Text("Done")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(TerminalColors.green)
                }
            } else {
                // Closed with activity: black spacer (with optional bounce)
                Rectangle()
                    .fill(.black)
                    .frame(width: closedNotchSize.width - cornerRadiusInsets.closed.top + (isBouncing ? 16 : 0))
            }

            // Right side - spinner when processing/pending
            if showClosedActivity {
                if isProcessing || hasPendingPermission {
                    ProcessingSpinner()
                        .matchedGeometryEffect(id: "spinner", in: activityNamespace, isSource: showClosedActivity)
                        .frame(width: viewModel.status == .opened ? 20 : sideWidth)
                } else if hasWaitingForInput {
                    // Small spacer on right for balanced layout
                    Rectangle()
                        .fill(.clear)
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

}
