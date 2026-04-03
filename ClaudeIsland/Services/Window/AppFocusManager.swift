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
    func focusSession(pid: Int?, cwd: String, isInTmux: Bool, sessionTitle: String? = nil) async -> Bool {
        if let cmux = cmuxPath {
            let cmuxPath = cmux
            let title = sessionTitle
            let project = URL(fileURLWithPath: cwd).lastPathComponent
            let sessionId = pid.map { String($0) }

            let _ = await Task.detached(priority: .userInitiated) {
                Self.focusViaCmux(cmux: cmuxPath, project: project, title: title, sessionId: sessionId)
            }.value
        }

        // Always activate the terminal app to bring it to front
        return Self.activateTerminalApp()
    }

    // MARK: - cmux Focus

    /// Focus a session by finding its pane via surface title matching
    private nonisolated static func focusViaCmux(cmux: String, project: String, title: String?, sessionId: String?) -> Bool {
        // Get all panes
        let panesOutput = runCmuxOutput(cmux, args: ["list-panes"])
        guard let panesOutput = panesOutput else { return false }

        // Parse pane IDs (e.g., "pane:1", "pane:3")
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

        // For each pane, check its surface title for a match
        for paneId in paneIds {
            let surfaceOutput = runCmuxOutput(cmux, args: ["list-pane-surfaces", "--pane", paneId])
            guard let surfaceOutput = surfaceOutput else { continue }

            let surfaceTitle = surfaceOutput.lowercased()

            // Match by project name (e.g., "claude-island" in "claude-island · mission-control...")
            if surfaceTitle.contains(project.lowercased()) {
                if runCmuxCommand(cmux, args: ["focus-pane", "--pane", paneId]) {
                    logger.info("Focused cmux pane \(paneId) by project: \(project, privacy: .public)")
                    return true
                }
            }
        }

        // Fallback: try find-window with workspace title
        if let title = title, !title.isEmpty {
            if runCmuxCommand(cmux, args: ["find-window", "--select", title]) {
                logger.info("Focused cmux by workspace title: \(title, privacy: .public)")
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
