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
    private var processMonitors: [Int: DispatchSourceProcess] = [:]
    private var graceTimers: [Int: DispatchWorkItem] = [:]

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

        // Safety-net cleanup for no-PID sessions (every 120s)
        staleCleanupTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
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

                // Don't cancel permissions on Stop — Stop just means Claude finished
                // a turn, not that permissions are invalid. Only PostToolUse means the
                // tool was actually handled (approved elsewhere or auto-approved).
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

    // MARK: - DispatchSource Process Monitoring

    /// Start monitoring a process for exit via DispatchSource
    private func startProcessMonitor(pid: Int, sessionId: String) {
        guard processMonitors[pid] == nil else { return }

        let source = DispatchSource.makeProcessSource(
            identifier: pid_t(pid),
            eventMask: .exit,
            queue: .main
        )

        source.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.handleProcessExit(pid: pid, sessionId: sessionId)
            }
        }

        processMonitors[pid] = source
        source.resume()

        // Safety: if the process is already dead, handle immediately
        if kill(pid_t(pid), 0) != 0 {
            handleProcessExit(pid: pid, sessionId: sessionId)
        }
    }

    /// Handle a detected process exit with a 5-second grace period
    private func handleProcessExit(pid: Int, sessionId: String) {
        // Cancel and remove the dispatch source
        if let source = processMonitors.removeValue(forKey: pid) {
            source.cancel()
        }

        // Cancel any existing grace timer for this PID
        graceTimers[pid]?.cancel()

        // Start a 5-second grace period before archiving
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.graceTimers.removeValue(forKey: pid)

            // If a new monitor was attached (process restarted), skip archiving
            if self.processMonitors[pid] != nil { return }

            // If the session got fresh activity (new PID assigned), skip archiving
            if let session = self.instances.first(where: { $0.sessionId == sessionId }),
               let currentPid = session.pid, currentPid != pid {
                return
            }

            self.archiveSession(sessionId: sessionId)
        }

        graceTimers[pid] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: workItem)
    }

    /// Stop monitoring a process and cancel any pending grace timer
    private func stopProcessMonitor(pid: Int) {
        if let source = processMonitors.removeValue(forKey: pid) {
            source.cancel()
        }
        if let timer = graceTimers.removeValue(forKey: pid) {
            timer.cancel()
        }
    }

    // MARK: - Stale Session Cleanup

    /// Safety-net cleanup for sessions discovered from disk that have no PID
    private func cleanupStaleSessions() {
        for session in instances {
            // Only clean up sessions with no PID (discovered from disk)
            // Sessions with PIDs are handled by DispatchSource monitors
            guard session.pid == nil else { continue }
            archiveSession(sessionId: session.sessionId)
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

                    // Only consider sessions active in the last 10 minutes
                    guard Date().timeIntervalSince(modDate) < 600 else { continue }

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
        // Diff PIDs: start monitors for new PIDs, stop for removed PIDs
        let oldPids = Set(instances.compactMap { $0.pid })
        let newPidSessions = sessions.compactMap { s -> (Int, String)? in
            guard let pid = s.pid else { return nil }
            return (pid, s.sessionId)
        }
        let newPids = Set(newPidSessions.map { $0.0 })

        // Start monitors for newly appeared PIDs
        for (pid, sessionId) in newPidSessions where !oldPids.contains(pid) {
            startProcessMonitor(pid: pid, sessionId: sessionId)
        }

        // Stop monitors for PIDs no longer in the session list
        for pid in oldPids.subtracting(newPids) {
            stopProcessMonitor(pid: pid)
        }

        instances = sessions
        // Only permission requests are "pending" (trigger panel open)
        // waitingForInput (Done) is NOT pending — it shows in the closed bar
        pendingInstances = sessions.filter { $0.phase.isWaitingForApproval }
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
