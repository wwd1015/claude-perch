//
//  AppFocusManager.swift
//  ClaudePerch
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

    func focusSession(pid: Int?, cwd: String, isInTmux: Bool, sessionTitle: String? = nil, sessionId: String? = nil, sessionSummary: String? = nil) async -> Bool {
        let cmux = cmuxPath
        let project = URL(fileURLWithPath: cwd).lastPathComponent
        let summary = sessionSummary
        let sid = sessionId
        let cwdPath = cwd

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                if let cmux = cmux {
                    // Build search terms
                    var terms: [String] = []
                    if let sid = sid { terms.append(String(sid.prefix(8))) }
                    if let summary = summary, !summary.isEmpty { terms.append(summary) }
                    terms.append(project)
                    terms.append(cwdPath)

                    Self.logger.debug("FOCUS: terms=\(terms.joined(separator: " | "), privacy: .public)")

                    // Get full tree and parse pane->title mapping
                    if let tree = Self.shell(cmux, ["tree", "--all"]) {
                        Self.logger.debug("FOCUS: tree output length=\(tree.count) first200=\(String(tree.prefix(200)), privacy: .public)")
                        // Parse: find lines with "pane pane:N" and their surface title in quotes
                        var currentPane: String? = nil
                        for line in tree.components(separatedBy: "\n") {
                            if let range = line.range(of: "pane:\\d+", options: .regularExpression) {
                                currentPane = String(line[range])
                            }
                            if line.contains("surface surface:"),
                               let pane = currentPane,
                               let q1 = line.firstIndex(of: "\"") {
                                let afterQ1 = line.index(after: q1)
                                if let q2 = line[afterQ1...].firstIndex(of: "\"") {
                                    let surfaceTitle = String(line[afterQ1..<q2]).lowercased()

                                    for term in terms {
                                        if surfaceTitle.contains(term.lowercased()) {
                                            Self.logger.debug("FOCUS: matched '\(term, privacy: .public)' in \(pane, privacy: .public)")
                                            let _ = Self.shell(cmux, ["focus-pane", "--pane", pane])
                                            Self.activateGhostty()
                                            continuation.resume(returning: true)
                                            return
                                        }
                                    }
                                }
                                currentPane = nil // Reset after processing surface
                            }
                        }
                    }

                    Self.logger.debug("FOCUS: no tree match, trying first unmatched pane")

                    // Fallback: focus the first pane that has a Claude session
                    // (any pane with a surface that's a terminal, not a shell prompt)
                    if let tree = Self.shell(cmux, ["tree", "--all"]) {
                        var panes: [String] = []
                        for line in tree.components(separatedBy: "\n") {
                            if let range = line.range(of: "pane:\\d+", options: .regularExpression) {
                                panes.append(String(line[range]))
                            }
                        }
                        // Try pane:1 first (most likely the unmatched session)
                        for pane in panes {
                            Self.logger.debug("FOCUS: fallback trying \(pane, privacy: .public)")
                            let _ = Self.shell(cmux, ["focus-pane", "--pane", pane])
                            Self.activateGhostty()
                            continuation.resume(returning: true)
                            return
                        }
                    }
                }

                // Last resort: just activate terminal
                Self.activateGhostty()
                continuation.resume(returning: false)
            }
        }
    }

    // MARK: - Shell

    private nonisolated static func shell(_ cmd: String, _ args: [String]) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: cmd)
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do { try process.run() } catch { return nil }

        let deadline = Date().addingTimeInterval(2.0)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning { process.terminate(); return nil }
        guard process.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Activate Ghostty

    private nonisolated static func activateGhostty() {
        for bid in ["com.mitchellh.ghostty", "com.cmuxterm.app"] {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bid).first,
               app.activate() {
                return
            }
        }
        // osascript fallback
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", "tell application \"Ghostty\" to activate"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
    }

    // MARK: - cmux Notification Suppression

    func suppressCmuxNotifications() {
        guard let cmux = cmuxPath else { return }
        DispatchQueue.global().async { _ = Self.shell(cmux, ["set-app-focus", "active"]) }
    }

    func restoreCmuxNotifications() {
        guard let cmux = cmuxPath else { return }
        DispatchQueue.global().async { _ = Self.shell(cmux, ["set-app-focus", "clear"]) }
    }
}
