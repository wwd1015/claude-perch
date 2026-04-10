//
//  AppFocusManager.swift
//  ClaudePerch
//
//  Focuses terminal windows using cmux CLI, tmux, or NSRunningApplication.
//

import AppKit
import os.log

actor AppFocusManager {
    static let shared = AppFocusManager()

    private nonisolated static let logger = Logger(subsystem: "com.claudeisland", category: "Focus")

    let cmuxPath: String?

    /// cmux terminal bundle ID
    private static let cmuxBundleId = "com.cmuxterm.app"

    private init() {
        let paths = [
            "/Applications/cmux.app/Contents/Resources/bin/cmux",
            "/usr/local/bin/cmux",
            "/opt/homebrew/bin/cmux"
        ]
        cmuxPath = paths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func focusSession(pid: Int?, cwd: String, isInTmux: Bool, sessionTitle: String? = nil, sessionId: String? = nil, sessionSummary: String? = nil, termBundleId: String? = nil) async -> Bool {
        let cmux = cmuxPath
        let project = URL(fileURLWithPath: cwd).lastPathComponent
        let summary = sessionSummary
        let sid = sessionId
        let cwdPath = cwd
        let bundleId = termBundleId

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {

                // Determine if this session is known to be in cmux
                let knownCmux = bundleId?.lowercased().contains("cmux") == true
                // Unknown terminal (discovered session) — we'll try cmux with session ID only
                let unknownTerminal = bundleId == nil || bundleId?.isEmpty == true

                if let cmux = cmux, (knownCmux || unknownTerminal) {
                    // For known cmux sessions: match on all tiers (session ID, summary, project)
                    // For unknown sessions: only match on session ID to avoid false positives
                    var termTiers: [[String]] = []
                    if let sid = sid { termTiers.append([String(sid.prefix(8))]) }
                    if knownCmux {
                        if let summary = summary, !summary.isEmpty { termTiers.append([summary]) }
                        termTiers.append([project, cwdPath])
                    }

                    if !termTiers.isEmpty, let tree = Self.shell(cmux, ["tree", "--all"]) {
                        // Parse workspace->pane->surface mappings
                        let paneSurfaces = Self.parseCmuxTree(tree)

                        // Try each tier across all surfaces (most specific match wins)
                        for tier in termTiers {
                            for entry in paneSurfaces {
                                let lowerTitle = entry.title.lowercased()
                                for term in tier {
                                    if lowerTitle.contains(term.lowercased()) {
                                        Self.logger.debug("FOCUS: cmux matched '\(term, privacy: .public)' in \(entry.pane, privacy: .public) ws=\(entry.workspace ?? "?", privacy: .public)")
                                        if let ws = entry.workspace {
                                            let _ = Self.shell(cmux, ["select-workspace", "--workspace", ws])
                                        }
                                        let _ = Self.shell(cmux, ["focus-pane", "--pane", entry.pane])
                                        Self.activateApp(bundleId: Self.cmuxBundleId, appName: "cmux")
                                        continuation.resume(returning: true)
                                        return
                                    }
                                }
                            }
                        }
                    }
                }

                // Tmux fallback: switch to the correct pane, then activate terminal
                if isInTmux, let pid = pid {
                    Self.logger.debug("FOCUS: trying tmux for pid=\(pid)")
                    let tmuxResult = Self.focusViaTmux(pid: pid, cwd: cwdPath)
                    if tmuxResult {
                        Self.activateApp(bundleId: bundleId, appName: nil)
                        continuation.resume(returning: true)
                        return
                    }
                }

                // Last resort: just activate the terminal app
                Self.activateApp(bundleId: bundleId, appName: nil)
                continuation.resume(returning: false)
            }
        }
    }

    // MARK: - cmux Tree Parser

    private struct CmuxSurface {
        let workspace: String?
        let pane: String
        let title: String
    }

    private nonisolated static func parseCmuxTree(_ tree: String) -> [CmuxSurface] {
        var results: [CmuxSurface] = []
        var currentWorkspace: String? = nil
        var currentPane: String? = nil

        for line in tree.components(separatedBy: "\n") {
            if let range = line.range(of: "workspace:\\d+", options: .regularExpression) {
                currentWorkspace = String(line[range])
            }
            if let range = line.range(of: "pane:\\d+", options: .regularExpression) {
                currentPane = String(line[range])
            }
            // Don't reset currentPane after each surface — panes have multiple surfaces (tabs)
            if line.contains("surface surface:"),
               let pane = currentPane,
               let q1 = line.firstIndex(of: "\"") {
                let afterQ1 = line.index(after: q1)
                if let q2 = line[afterQ1...].firstIndex(of: "\"") {
                    let title = String(line[afterQ1..<q2])
                    results.append(CmuxSurface(workspace: currentWorkspace, pane: pane, title: title))
                }
            }
        }
        return results
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

    // MARK: - Tmux Focus Fallback

    private nonisolated static func focusViaTmux(pid: Int, cwd: String) -> Bool {
        let tmuxPaths = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
        guard let tmuxPath = tmuxPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return false
        }

        guard let output = shell(tmuxPath, ["list-panes", "-a", "-F", "#{session_name}:#{window_index}.#{pane_index} #{pane_pid}"]) else {
            return false
        }

        let tree = ProcessTreeBuilder.shared.buildTree()

        for line in output.components(separatedBy: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1)
            guard parts.count == 2, let panePid = Int(parts[1]) else { continue }
            let targetString = String(parts[0])

            if ProcessTreeBuilder.shared.isDescendant(targetPid: pid, ofAncestor: panePid, tree: tree) {
                let sessionWindow: String
                if let dotIndex = targetString.lastIndex(of: ".") {
                    sessionWindow = String(targetString[targetString.startIndex..<dotIndex])
                } else {
                    sessionWindow = targetString
                }

                _ = shell(tmuxPath, ["select-window", "-t", sessionWindow])
                _ = shell(tmuxPath, ["select-pane", "-t", targetString])
                logger.debug("FOCUS: tmux switched to \(targetString, privacy: .public)")
                return true
            }
        }

        return false
    }

    // MARK: - App Activation

    /// Activate a terminal app. Tries bundle ID first, then osascript fallback.
    private nonisolated static func activateApp(bundleId: String?, appName: String?) {
        // Try preferred bundle ID
        if let bid = bundleId, !bid.isEmpty {
            if activateByBundleId(bid) { return }
        }

        // Try osascript with app name (reliable for cmux and other apps)
        if let name = appName, !name.isEmpty {
            if activateByOsascript(name) { return }
        }

        // Fallback: try known terminal bundle IDs in a deterministic order
        let orderedBundleIds = [
            "com.cmuxterm.app",
            "com.mitchellh.ghostty",
            "com.googlecode.iterm2",
            "com.apple.Terminal",
            "net.kovidgoyal.kitty",
            "com.github.wez.wezterm",
            "dev.warp.Warp-Stable",
            "io.alacritty"
        ]
        for bid in orderedBundleIds {
            if activateByBundleId(bid) { return }
        }
    }

    private nonisolated static func activateByBundleId(_ bundleId: String) -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else {
            return false
        }

        app.unhide()

        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config)
            return true
        }

        return app.activate()
    }

    private nonisolated static func activateByOsascript(_ appName: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "tell application \"\(appName)\" to activate"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
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
