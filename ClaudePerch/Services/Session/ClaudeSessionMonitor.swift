//
//  ClaudeSessionMonitor.swift
//  ClaudePerch
//
//  MainActor wrapper around SessionStore for UI binding.
//  Publishes SessionState arrays for SwiftUI observation.
//

import AppKit
import Combine
import Foundation

@MainActor
class ClaudeSessionMonitor: ObservableObject {
    @Published var instances: [SessionState] = []
    @Published var pendingInstances: [SessionState] = []

    private var cancellables = Set<AnyCancellable>()

    init() {
        SessionStore.shared.sessionsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessions in
                self?.updateFromSessions(sessions)
            }
            .store(in: &cancellables)

        InterruptWatcherManager.shared.delegate = self
    }

    // MARK: - Monitoring Lifecycle

    private var staleCleanupTimer: Timer?

    func startMonitoring() {
        // Discover existing sessions on launch (like Vibe Island)
        discoverExistingSessions()

        // Periodically clean up stale sessions (every 60s)
        staleCleanupTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.cleanupStaleSessions()
            }
        }

        HookSocketServer.shared.start(
            onEvent: { event in
                Task {
                    await SessionStore.shared.process(.hookReceived(event))
                }

                if event.sessionPhase == .processing {
                    Task { @MainActor in
                        InterruptWatcherManager.shared.startWatching(
                            sessionId: event.sessionId,
                            cwd: event.cwd
                        )
                    }
                }

                if event.status == "ended" {
                    Task { @MainActor in
                        InterruptWatcherManager.shared.stopWatching(sessionId: event.sessionId)
                    }
                }

                if event.event == "Stop" {
                    HookSocketServer.shared.cancelPendingPermissions(sessionId: event.sessionId)
                }

                if event.event == "PostToolUse", let toolUseId = event.toolUseId {
                    HookSocketServer.shared.cancelPendingPermission(toolUseId: toolUseId)
                }
            },
            onPermissionFailure: { sessionId, toolUseId in
                Task {
                    await SessionStore.shared.process(
                        .permissionSocketFailed(sessionId: sessionId, toolUseId: toolUseId)
                    )
                }
            },
            onPermissionExpired: { sessionId, toolUseId in
                Task {
                    await SessionStore.shared.process(
                        .permissionSocketFailed(sessionId: sessionId, toolUseId: toolUseId)
                    )
                }
            }
        )
    }

    func stopMonitoring() {
        HookSocketServer.shared.stop()
    }

    // MARK: - Permission Handling

    func approvePermission(sessionId: String) {
        Task {
            guard let session = await SessionStore.shared.session(for: sessionId),
                  let permission = session.activePermission else {
                return
            }

            HookSocketServer.shared.respondToPermission(
                toolUseId: permission.toolUseId,
                decision: "allow"
            )

            await SessionStore.shared.process(
                .permissionApproved(sessionId: sessionId, toolUseId: permission.toolUseId)
            )
        }
    }

    /// Approve and add a permanent "always allow" rule
    func approveAlwaysPermission(sessionId: String) {
        Task {
            guard let session = await SessionStore.shared.session(for: sessionId),
                  let permission = session.activePermission else {
                return
            }

            HookSocketServer.shared.respondToPermission(
                toolUseId: permission.toolUseId,
                decision: "allowAlways"
            )

            await SessionStore.shared.process(
                .permissionApproved(sessionId: sessionId, toolUseId: permission.toolUseId)
            )
        }
    }

    /// Answer an AskUserQuestion with the selected option text
    func answerQuestion(sessionId: String, selectedOption: String) {
        Task {
            guard let session = await SessionStore.shared.session(for: sessionId),
                  let permission = session.activePermission else {
                return
            }

            HookSocketServer.shared.respondToPermission(
                toolUseId: permission.toolUseId,
                decision: "answer",
                reason: selectedOption
            )

            await SessionStore.shared.process(
                .permissionApproved(sessionId: sessionId, toolUseId: permission.toolUseId)
            )
        }
    }

    func denyPermission(sessionId: String, reason: String?) {
        Task {
            guard let session = await SessionStore.shared.session(for: sessionId),
                  let permission = session.activePermission else {
                return
            }

            HookSocketServer.shared.respondToPermission(
                toolUseId: permission.toolUseId,
                decision: "deny",
                reason: reason
            )

            await SessionStore.shared.process(
                .permissionDenied(sessionId: sessionId, toolUseId: permission.toolUseId, reason: reason)
            )
        }
    }

    /// Archive (remove) a session from the instances list
    func archiveSession(sessionId: String) {
        Task {
            await SessionStore.shared.process(.sessionEnded(sessionId: sessionId))
        }
    }

    // MARK: - Stale Session Cleanup

    /// Remove sessions whose processes have died and have been inactive
    private func cleanupStaleSessions() {
        for session in instances {
            guard let pid = session.pid else { continue }
            // Check if process is still alive (kill with signal 0 just checks existence)
            if kill(pid_t(pid), 0) != 0 {
                let staleDuration = Date().timeIntervalSince(session.lastActivity)
                if staleDuration > 120 { // 2 minutes inactive + dead process
                    archiveSession(sessionId: session.sessionId)
                }
            }
        }
    }

    // MARK: - Session Discovery (on launch)

    /// Scan ~/.claude/projects/ for recently active sessions and add them
    private func discoverExistingSessions() {
        Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            let projectsDir = NSHomeDirectory() + "/.claude/projects"

            guard let projectDirs = try? fileManager.contentsOfDirectory(atPath: projectsDir) else { return }

            for projectDir in projectDirs {
                // Skip hidden dirs and non-project dirs
                guard !projectDir.hasPrefix("."), projectDir.hasPrefix("-") else { continue }

                let fullProjectDir = projectsDir + "/" + projectDir
                guard let files = try? fileManager.contentsOfDirectory(atPath: fullProjectDir) else { continue }

                // Find JSONL files modified in the last 30 minutes
                let jsonlFiles = files.filter { $0.hasSuffix(".jsonl") && !$0.hasPrefix("agent-") }

                for jsonlFile in jsonlFiles {
                    let filePath = fullProjectDir + "/" + jsonlFile
                    guard let attrs = try? fileManager.attributesOfItem(atPath: filePath),
                          let modDate = attrs[.modificationDate] as? Date else { continue }

                    // Only consider sessions active in the last 30 minutes
                    guard Date().timeIntervalSince(modDate) < 1800 else { continue }

                    let sessionId = String(jsonlFile.dropLast(6)) // Remove .jsonl

                    // Convert dir name back to cwd path
                    // e.g., "-Users-alan-Documents-GitHub-claude-perch" -> "/Users/alan/Documents/GitHub/claude-perch"
                    // Can't just replace all hyphens because path components may contain hyphens
                    // Try progressive reconstruction: replace hyphens one by one and check if path exists
                    let cwd = Self.reconstructCwd(from: projectDir)

                    // Create a synthetic hook event to register the session
                    let event = HookEvent(
                        sessionId: sessionId,
                        cwd: cwd,
                        event: "SessionStart",
                        status: "idle",
                        pid: nil,
                        tty: nil,
                        tool: nil,
                        toolInput: nil,
                        toolUseId: nil,
                        notificationType: nil,
                        message: nil
                    )

                    await SessionStore.shared.process(.hookReceived(event))

                    // Load the conversation history
                    await SessionStore.shared.process(.loadHistory(sessionId: sessionId, cwd: cwd))
                }
            }
        }
    }

    /// Reconstruct the cwd path from the Claude projects directory name
    /// e.g., "-Users-alan-Documents-GitHub-claude-perch" -> "/Users/alan/Documents/GitHub/claude-perch"
    private nonisolated static func reconstructCwd(from dirName: String) -> String {
        let withoutPrefix = String(dirName.dropFirst()) // Remove leading "-"
        let parts = withoutPrefix.components(separatedBy: "-")

        // Try building the path progressively, checking if each prefix exists
        var bestPath = "/" + withoutPrefix.replacingOccurrences(of: "-", with: "/")
        var currentPath = ""

        for i in 0..<parts.count {
            if currentPath.isEmpty {
                currentPath = "/" + parts[i]
            } else {
                // Try both "/" (new component) and "-" (part of same component)
                let withSlash = currentPath + "/" + parts[i]
                let withHyphen = currentPath + "-" + parts[i]

                if FileManager.default.fileExists(atPath: withSlash) {
                    currentPath = withSlash
                } else if FileManager.default.fileExists(atPath: withHyphen) {
                    currentPath = withHyphen
                } else {
                    // Neither exists yet, prefer slash (building the path up)
                    currentPath = withSlash
                }
            }
        }

        // If the reconstructed path exists, use it. Otherwise fall back to simple replacement.
        if FileManager.default.fileExists(atPath: currentPath) {
            return currentPath
        }
        return bestPath
    }

    // MARK: - State Update

    private func updateFromSessions(_ sessions: [SessionState]) {
        instances = sessions
        pendingInstances = sessions.filter { $0.needsAttention }
    }

    // MARK: - History Loading (for UI)

    /// Request history load for a session
    func loadHistory(sessionId: String, cwd: String) {
        Task {
            await SessionStore.shared.process(.loadHistory(sessionId: sessionId, cwd: cwd))
        }
    }
}

// MARK: - Interrupt Watcher Delegate

extension ClaudeSessionMonitor: JSONLInterruptWatcherDelegate {
    nonisolated func didDetectInterrupt(sessionId: String) {
        Task {
            await SessionStore.shared.process(.interruptDetected(sessionId: sessionId))
        }

        Task { @MainActor in
            InterruptWatcherManager.shared.stopWatching(sessionId: sessionId)
        }
    }
}
