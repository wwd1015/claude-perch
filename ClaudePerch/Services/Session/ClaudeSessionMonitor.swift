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

    /// Discover running Claude CLI sessions by scanning processes and matching to JSONL files
    private func discoverExistingSessions() {
        Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            let projectsDir = AppSettings.claudeProjectsPath

            // Step 1: Find running Claude CLI processes
            let runningProcesses = Self.findRunningClaudeSessions()
            guard !runningProcesses.isEmpty else { return }

            // Step 2: Build cwd -> project dir mapping and session file index
            guard let projectDirs = try? fileManager.contentsOfDirectory(atPath: projectsDir) else { return }

            // Map: cwd path -> (projectDir, [(sessionId, filePath, modDate)])
            var cwdToSessions: [String: [(sessionId: String, path: String, modDate: Date)]] = [:]
            var sessionFiles: [String: (path: String, cwd: String)] = [:]

            for projectDir in projectDirs {
                guard !projectDir.hasPrefix("."), projectDir.hasPrefix("-") else { continue }
                let fullProjectDir = projectsDir + "/" + projectDir
                guard let files = try? fileManager.contentsOfDirectory(atPath: fullProjectDir) else { continue }

                let cwd = Self.reconstructCwd(from: projectDir)

                for file in files where file.hasSuffix(".jsonl") && !file.hasPrefix("agent-") {
                    let sessionId = String(file.dropLast(6))
                    let filePath = fullProjectDir + "/" + file
                    sessionFiles[sessionId] = (filePath, cwd)

                    if let attrs = try? fileManager.attributesOfItem(atPath: filePath),
                       let modDate = attrs[.modificationDate] as? Date {
                        cwdToSessions[cwd, default: []].append((sessionId, filePath, modDate))
                    }
                }
            }

            // Step 3: Create sessions for each running process
            for proc in runningProcesses {
                var sessionId = proc.sessionId
                var cwd = proc.cwd

                if let sid = sessionId, let fileInfo = sessionFiles[sid] {
                    // Known session ID — use its cwd from JSONL path
                    cwd = fileInfo.cwd
                } else if sessionId == nil, let procCwd = cwd {
                    // No session ID in command line — find most recent JSONL for this cwd
                    if let sessions = cwdToSessions[procCwd] {
                        let sorted = sessions.sorted { $0.modDate > $1.modDate }
                        sessionId = sorted.first?.sessionId
                    }
                }

                // Still no cwd? Get it from the process
                if cwd == nil {
                    cwd = ProcessTreeBuilder.shared.getWorkingDirectory(forPid: proc.pid)
                    // Try matching cwd to JSONL again
                    if sessionId == nil, let c = cwd, let sessions = cwdToSessions[c] {
                        let sorted = sessions.sorted { $0.modDate > $1.modDate }
                        sessionId = sorted.first?.sessionId
                    }
                }

                guard let finalSessionId = sessionId, let finalCwd = cwd else { continue }

                // Detect terminal type from process tree
                let termBundleId = Self.detectTerminalBundleId(forPid: proc.pid)

                let event = HookEvent(
                    sessionId: finalSessionId,
                    cwd: finalCwd,
                    event: "SessionStart",
                    status: "waiting_for_input",
                    pid: proc.pid,
                    tty: nil,
                    tool: nil,
                    toolInput: nil,
                    toolUseId: nil,
                    notificationType: nil,
                    message: nil,
                    termBundleId: termBundleId
                )

                await SessionStore.shared.process(.hookReceived(event))
                await SessionStore.shared.process(.loadHistory(sessionId: finalSessionId, cwd: finalCwd))
            }
        }
    }

    /// Detect the terminal app bundle ID by walking up the process tree
    private nonisolated static func detectTerminalBundleId(forPid pid: Int) -> String? {
        let tree = ProcessTreeBuilder.shared.buildTree()
        var current = pid
        var depth = 0

        while current > 1 && depth < 20 {
            guard let info = tree[current] else { break }
            let cmd = info.command.lowercased()

            if cmd.contains("cmux") { return "com.cmuxterm.app" }
            if cmd.contains("ghostty") { return "com.mitchellh.ghostty" }
            if cmd.contains("iterm") { return "com.googlecode.iterm2" }
            if cmd.contains("terminal") && cmd.contains("apple") { return "com.apple.Terminal" }
            if cmd.contains("wezterm") { return "com.github.wez.wezterm" }
            if cmd.contains("kitty") { return "net.kovidgoyal.kitty" }
            if cmd.contains("alacritty") { return "io.alacritty" }

            current = info.ppid
            depth += 1
        }
        return nil
    }

    /// Find running Claude CLI processes, with or without --session-id
    private nonisolated static func findRunningClaudeSessions() -> [(sessionId: String?, pid: Int, cwd: String?)] {
        guard let output = ProcessExecutor.shared.runSyncOrNil(
            "/bin/ps", arguments: ["-ww", "-eo", "pid,comm"]
        ) else { return [] }

        // First pass: find all Claude PIDs by command name
        var claudePids: [Int] = []
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard parts.count >= 2, let pid = Int(parts[0]) else { continue }
            let comm = parts[1...].joined(separator: " ")
            // Match "claude" or paths ending in "/claude" but not helpers/hooks
            let lower = comm.lowercased()
            guard lower == "claude" || lower.hasSuffix("/claude") else { continue }
            guard !lower.contains("claude-perch"), !lower.contains("claude helper") else { continue }
            claudePids.append(pid)
        }

        guard !claudePids.isEmpty else { return [] }

        // Second pass: get full args for matched PIDs to extract session IDs
        guard let argsOutput = ProcessExecutor.shared.runSyncOrNil(
            "/bin/ps", arguments: ["-ww", "-o", "pid,args", "-p", claudePids.map(String.init).joined(separator: ",")]
        ) else { return [] }

        var results: [(sessionId: String?, pid: Int, cwd: String?)] = []
        for line in argsOutput.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard parts.count >= 2, let pid = Int(parts[0]) else { continue }

            // Skip VS Code / IDE extension processes (they use --output-format stream-json)
            let fullArgs = parts[1...].joined(separator: " ")
            if fullArgs.contains("--output-format") || fullArgs.contains("native-binary") {
                continue
            }

            var sessionId: String? = nil
            if let idx = parts.firstIndex(of: "--session-id"), idx + 1 < parts.count {
                let sid = parts[idx + 1]
                if sid.count >= 8, sid.contains("-") {
                    sessionId = sid
                }
            }

            // Get cwd for processes without session ID
            let cwd: String? = sessionId == nil
                ? ProcessTreeBuilder.shared.getWorkingDirectory(forPid: pid)
                : nil

            results.append((sessionId: sessionId, pid: pid, cwd: cwd))
        }
        return results
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
