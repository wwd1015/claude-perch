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

    /// Logger must be nonisolated static to avoid MainActor isolation issues
    private nonisolated static let logger = Logger(subsystem: "com.claudeisland", category: "Focus")

    private let cmuxPath: String?

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
    /// Runs cmux on a background thread with a timeout to prevent UI freezes.
    func focusSession(pid: Int?, cwd: String, isInTmux: Bool, sessionTitle: String? = nil) async -> Bool {
        if let cmux = cmuxPath {
            // Run cmux on a detached task to avoid blocking the actor
            let cmuxPath = cmux
            let title = sessionTitle
            let dir = cwd

            let focused = await Task.detached(priority: .userInitiated) {
                return Self.runCmuxFocus(cmux: cmuxPath, title: title, cwd: dir)
            }.value

            if focused {
                return true
            }
        }

        // Fallback: just activate the terminal app
        return Self.activateTerminalApp()
    }

    // MARK: - cmux Focus (runs off main actor)

    /// Run cmux commands synchronously with a 2-second timeout.
    /// This is nonisolated and runs on a background thread to prevent actor deadlocks.
    private nonisolated static func runCmuxFocus(cmux: String, title: String?, cwd: String) -> Bool {
        // Try find-window --select with session title
        if let title = title, !title.isEmpty {
            if runCmuxCommand(cmux, args: ["find-window", "--select", title]) {
                logger.info("Focused cmux by title: \(title, privacy: .public)")
                return true
            }
        }

        // Try with directory name
        let dirName = URL(fileURLWithPath: cwd).lastPathComponent
        if runCmuxCommand(cmux, args: ["find-window", "--select", dirName]) {
            logger.info("Focused cmux by dir: \(dirName, privacy: .public)")
            return true
        }

        return false
    }

    /// Execute a cmux command with a 2-second timeout. Returns true on success.
    private nonisolated static func runCmuxCommand(_ cmux: String, args: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cmux)
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()

            // Poll with 2-second timeout
            let deadline = Date().addingTimeInterval(2.0)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }

            if process.isRunning {
                process.terminate()
                logger.warning("cmux timed out: \(args.joined(separator: " "), privacy: .public)")
                return false
            }

            return process.terminationStatus == 0
        } catch {
            logger.debug("cmux error: \(error.localizedDescription, privacy: .public)")
            return false
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
