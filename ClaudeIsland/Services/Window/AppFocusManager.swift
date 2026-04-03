//
//  AppFocusManager.swift
//  ClaudeIsland
//
//  Focuses terminal windows using cmux CLI or NSRunningApplication.
//

import AppKit
import os.log

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
        cmuxPath = paths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Focus the terminal for a Claude session
    func focusSession(pid: Int?, cwd: String, isInTmux: Bool, sessionTitle: String? = nil, sessionId: String? = nil, sessionSummary: String? = nil) async -> Bool {
        let cmux = cmuxPath
        let project = URL(fileURLWithPath: cwd).lastPathComponent
        let summary = sessionSummary
        let sid = sessionId

        Self.logger.error("FOCUS DEBUG: focusSession called! project=\(project, privacy: .public) summary=\(summary ?? "nil", privacy: .public) sid=\(sid ?? "nil", privacy: .public) cmux=\(cmux != nil ? "YES" : "NO", privacy: .public)")

        // Run focus logic on a background thread to never block UI
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var focused = false

                if let cmux = cmux {
                    // Build search terms in priority order
                    var searchTerms: [String] = []
                    if let sid = sid { searchTerms.append(String(sid.prefix(8))) }
                    if let summary = summary, !summary.isEmpty { searchTerms.append(summary) }
                    searchTerms.append(project)

                    focused = Self.focusCmuxPane(cmux: cmux, searchTerms: searchTerms)
                }

                // Always activate Ghostty/terminal
                Self.activateGhostty()

                continuation.resume(returning: focused)
            }
        }
    }

    // MARK: - cmux Pane Focus

    /// Find and focus the right cmux pane by matching search terms against surface titles
    private nonisolated static func focusCmuxPane(cmux: String, searchTerms: [String]) -> Bool {
        logger.error("FOCUS DEBUG: starting with terms: \(searchTerms.joined(separator: ", "), privacy: .public)")

        // Get pane list
        guard let panesRaw = shell(cmux, ["list-panes"]) else {
            logger.error("FOCUS DEBUG: cmux list-panes FAILED")
            return false
        }
        logger.error("FOCUS DEBUG: panes raw: \(panesRaw, privacy: .public)")

        let paneIds = panesRaw.components(separatedBy: "\n")
            .compactMap { line -> String? in
                guard let match = line.range(of: "pane:\\d+", options: .regularExpression) else { return nil }
                return String(line[match])
            }

        logger.error("FOCUS DEBUG: found \(paneIds.count) panes: \(paneIds.joined(separator: ", "), privacy: .public)")

        // Get surface titles for each pane
        for paneId in paneIds {
            guard let surfaceRaw = shell(cmux, ["list-pane-surfaces", "--pane", paneId]) else {
                logger.error("FOCUS DEBUG: list-pane-surfaces FAILED for \(paneId, privacy: .public)")
                continue
            }
            let titleLower = surfaceRaw.lowercased()
            logger.error("FOCUS DEBUG: \(paneId, privacy: .public) surface: \(titleLower, privacy: .public)")

            // Try each search term
            for term in searchTerms {
                if titleLower.contains(term.lowercased()) {
                    logger.error("FOCUS DEBUG: MATCHED '\(term, privacy: .public)' in \(paneId, privacy: .public), calling focus-pane")
                    if let result = shell(cmux, ["focus-pane", "--pane", paneId]) {
                        logger.error("FOCUS DEBUG: focus-pane SUCCESS: \(result, privacy: .public)")
                        return true
                    } else {
                        logger.error("FOCUS DEBUG: focus-pane FAILED for \(paneId, privacy: .public)")
                    }
                }
            }
        }

        logger.error("FOCUS DEBUG: NO MATCH for terms: \(searchTerms.joined(separator: ", "), privacy: .public)")
        return false
    }

    /// Run a shell command synchronously with 2s timeout, return stdout
    private nonisolated static func shell(_ cmd: String, _ args: [String]) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: cmd)
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            logger.debug("Failed to run \(cmd): \(error.localizedDescription, privacy: .public)")
            return nil
        }

        // Wait with timeout
        let deadline = Date().addingTimeInterval(2.0)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning {
            process.terminate()
            logger.warning("Timeout: \(cmd) \(args.joined(separator: " "), privacy: .public)")
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    /// Activate Ghostty via NSRunningApplication + osascript fallback
    private nonisolated static func activateGhostty() {
        // Try NSRunningApplication first
        let bundleIds = ["com.mitchellh.ghostty", "com.cmuxterm.app", "com.googlecode.iterm2", "com.apple.Terminal"]
        for bundleId in bundleIds {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
                if app.activate() {
                    logger.info("Activated \(bundleId, privacy: .public)")
                    return
                }
            }
        }

        // Fallback: osascript
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "tell application \"Ghostty\" to activate"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        logger.info("Activated Ghostty via osascript")
    }

    // MARK: - cmux Notification Suppression

    func suppressCmuxNotifications() {
        guard let cmux = cmuxPath else { return }
        DispatchQueue.global().async {
            _ = Self.shell(cmux, ["set-app-focus", "active"])
        }
    }

    func restoreCmuxNotifications() {
        guard let cmux = cmuxPath else { return }
        DispatchQueue.global().async {
            _ = Self.shell(cmux, ["set-app-focus", "clear"])
        }
    }
}
