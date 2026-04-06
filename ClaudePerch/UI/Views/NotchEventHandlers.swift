//
//  NotchEventHandlers.swift
//  ClaudePerch
//
//  Event handler methods for NotchView, extracted to reduce file size.
//  Uses extension NotchView to access @State vars.
//

import AppKit
import SwiftUI

// MARK: - Event Handlers

extension NotchView {
    func handleProcessingChange() {
        if isAnyProcessing || hasPendingPermission {
            // Show claude activity when processing or waiting for permission
            activityCoordinator.showActivity(type: .claude)
            isVisible = true
        } else if hasWaitingForInput {
            // Keep visible for waiting-for-input but hide the processing spinner
            activityCoordinator.hideActivity()
            isVisible = true

            // Auto-close the panel for Done state — show expanded closed bar instead
            if viewModel.status == .opened {
                viewModel.notchClose()
            }
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

    func handleStatusChange(from oldStatus: NotchStatus, to newStatus: NotchStatus) {
        switch newStatus {
        case .opened, .popping:
            isVisible = true
            // Clear completion queue when manually opened (user acknowledged)
            if viewModel.openReason == .click || viewModel.openReason == .hover {
                completionQueue.cancelAll()
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

    func handlePendingSessionsChange(_ sessions: [SessionState]) {
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

    func handleWaitingForInputChange(_ instances: [SessionState]) {
        // Get sessions that are now waiting for input
        let waitingForInputSessions = instances.filter { $0.phase == .waitingForInput }
        let currentIds = Set(waitingForInputSessions.map { $0.stableId })
        let newWaitingIds = currentIds.subtracting(previousWaitingForInputIds)

        // Enqueue newly waiting sessions into the completion queue
        if !newWaitingIds.isEmpty {
            let newlyWaitingSessions = waitingForInputSessions.filter { newWaitingIds.contains($0.stableId) }

            // Enqueue each new completion
            for session in newlyWaitingSessions {
                completionQueue.enqueue(sessionId: session.stableId)
            }

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

            // Close the panel if open — Done state shows expanded closed bar, not popup
            if viewModel.status == .opened {
                viewModel.notchClose()
            }

            // Trigger bounce animation to get user's attention
            DispatchQueue.main.async {
                isBouncing = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    isBouncing = false
                }
            }
        }

        previousWaitingForInputIds = currentIds
    }

    /// Determine if notification sound should play for the given sessions
    /// Returns true if ANY session is not actively focused
    func shouldPlayNotificationSound(for sessions: [SessionState]) async -> Bool {
        for session in sessions {
            guard let pid = session.pid else {
                // No PID means we can't check focus, assume not focused
                return true
            }

            let isFocused = await TerminalVisibilityDetector.isSessionFocused(
                sessionPid: pid,
                cwd: session.cwd,
                tty: session.tty,
                sessionId: session.sessionId,
                isInTmux: session.isInTmux
            )
            if !isFocused {
                return true
            }
        }

        return false
    }

    // MARK: - Global Hotkeys

    func startGlobalHotkeys() {
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
