//
//  AppFocusManager.swift
//  ClaudeIsland
//
//  Focuses terminal windows using cmux CLI or NSRunningApplication.
//  Supports cmux (Ghostty-based multiplexer) and plain terminals.
//

import AppKit
import os.log

/// Focuses terminal apps and panes without requiring yabai
actor AppFocusManager {
    static let shared = AppFocusManager()

    private nonisolated static let logger = Logger(subsystem: "com.claudeisland", category: "Focus")

    let cmuxPath: String?

    private init() {
        let paths = [
            "/Applications/cmux.app/Contents/Resources/bin/cmux",
            "/usr/local/bin/cmux",
            "/opt/homebrew/bin/cmux"
        ]
        var found: String? = nil
        for path in paths {
            if FileManager.default.isExecutableFile(atPath: path) {
                found = path
                break
            }
        }
        cmuxPath = found
    }

    /// Focus the terminal for a Claude session.
    func focusSession(pid: Int?, cwd: String, isInTmux: Bool, sessionTitle: String? = nil, sessionId: String? = nil, sessionSummary: String? = nil) async -> Bool {
        if let cmux = cmuxPath {
            let cmuxPath = cmux
            let title = sessionTitle
            let project = URL(fileURLWithPath: cwd).lastPathComponent
            let sid = sessionId
            let summary = sessionSummary

            let _ = await Task.detached(priority: .userInitiated) {
                Self.focusViaCmux(cmux: cmuxPath, project: project, title: title, sessionId: sid, summary: summary)
            }.value
        }

        // Always activate the terminal app to bring it to front
        return Self.activateTerminalApp()
    }

    // MARK: - cmux Focus

    /// Focus a session by finding its pane via surface title matching.
    /// Tries: session ID prefix > project name > session title > workspace title
    private nonisolated static func focusViaCmux(cmux: String, project: String, title: String?, sessionId: String?, summary: String? = nil) -> Bool {
        // Get all panes
        let panesOutput = runCmuxOutput(cmux, args: ["list-panes"])
        guard let panesOutput = panesOutput else { return false }

        let paneIds = panesOutput.components(separatedBy: "\n")
            .compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "* ", with: "")
                guard let spaceIdx = trimmed.firstIndex(of: " ") else {
                    return trimmed.isEmpty ? nil : trimmed
                }
                return String(trimmed[trimmed.startIndex..<spaceIdx])
            }
            .filter { $0.hasPrefix("pane:") }

        // Build a list of (paneId, surfaceTitle) pairs
        var paneSurfaces: [(pane: String, title: String)] = []
        for paneId in paneIds {
            if let output = runCmuxOutput(cmux, args: ["list-pane-surfaces", "--pane", paneId]) {
                paneSurfaces.append((pane: paneId, title: output.lowercased()))
            }
        }

        // Strategy 1: Match by session ID prefix (most precise)
        // Surface titles end with session UUID like "· f392f138-87a8-4e"
        if let sid = sessionId {
            let shortId = String(sid.prefix(8)).lowercased()
            for ps in paneSurfaces {
                if ps.title.contains(shortId) {
                    if runCmuxCommand(cmux, args: ["focus-pane", "--pane", ps.pane]) {
                        logger.info("Focused pane \(ps.pane) by sessionId: \(shortId, privacy: .public)")
                        return true
                    }
                }
            }
        }

        // Strategy 2: Match by session summary (e.g., "mission-control-dashboard-review")
        if let summary = summary, !summary.isEmpty {
            let summaryLower = summary.lowercased()
            for ps in paneSurfaces {
                if ps.title.contains(summaryLower) {
                    if runCmuxCommand(cmux, args: ["focus-pane", "--pane", ps.pane]) {
                        logger.info("Focused pane \(ps.pane) by summary: \(summary, privacy: .public)")
                        return true
                    }
                }
            }
        }

        // Strategy 3: Match by project name
        let projectLower = project.lowercased()
        for ps in paneSurfaces {
            if ps.title.contains(projectLower) {
                if runCmuxCommand(cmux, args: ["focus-pane", "--pane", ps.pane]) {
                    logger.info("Focused pane \(ps.pane) by project: \(project, privacy: .public)")
                    return true
                }
            }
        }

        // Strategy 3: Match by session title/summary
        if let title = title, !title.isEmpty {
            let titleLower = title.lowercased()
            for ps in paneSurfaces {
                if ps.title.contains(titleLower) {
                    if runCmuxCommand(cmux, args: ["focus-pane", "--pane", ps.pane]) {
                        logger.info("Focused pane \(ps.pane) by title: \(title, privacy: .public)")
                        return true
                    }
                }
            }

            // Also try find-window for workspace-level match
            if runCmuxCommand(cmux, args: ["find-window", "--select", title]) {
                logger.info("Focused workspace by title: \(title, privacy: .public)")
                return true
            }
        }

        return false
    }

    /// Run a cmux command and return stdout
    private nonisolated static func runCmuxOutput(_ cmux: String, args: [String]) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: cmux)
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let deadline = Date().addingTimeInterval(2.0)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning { process.terminate(); return nil }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    /// Execute a cmux command with timeout. Returns true on success.
    private nonisolated static func runCmuxCommand(_ cmux: String, args: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cmux)
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let deadline = Date().addingTimeInterval(2.0)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning { process.terminate(); return false }
            return process.terminationStatus == 0
        } catch {
            return nil != nil // always false
        }
    }

    // MARK: - cmux Notification Suppression

    func suppressCmuxNotifications() {
        guard let cmux = cmuxPath else { return }
        Task.detached {
            Self.runCmuxCommand(cmux, args: ["set-app-focus", "active"])
        }
    }

    func restoreCmuxNotifications() {
        guard let cmux = cmuxPath else { return }
        Task.detached {
            Self.runCmuxCommand(cmux, args: ["set-app-focus", "clear"])
        }
    }

    // MARK: - Generic App Activation

    private nonisolated static func activateTerminalApp() -> Bool {
        let bundleIds = [
            "com.mitchellh.ghostty",
            "com.cmuxterm.app",
            "com.googlecode.iterm2",
            "com.apple.Terminal"
        ]
        for bundleId in bundleIds {
            let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            if let app = apps.first, app.activate() {
                logger.info("Activated: \(bundleId, privacy: .public)")
                return true
            }
        }
        return false
    }
}
