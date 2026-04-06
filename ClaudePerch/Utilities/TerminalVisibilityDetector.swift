//
//  TerminalVisibilityDetector.swift
//  ClaudePerch
//
//  Detects if terminal windows are visible on current space.
//  Two-level detection:
//    Level 1 (fast): Is any terminal app frontmost?
//    Level 2 (background): Is the specific session's tab/pane visible?
//

import AppKit
import CoreGraphics

struct TerminalVisibilityDetector {

    // MARK: - Cache

    /// Cached tab-level focus result to avoid hammering AppleScript (~100ms per call)
    private static var tabFocusCache: (key: String, result: Bool, time: Date)?
    private static let cacheTTL: TimeInterval = 1.5

    private static func cacheKey(sessionPid: Int, cwd: String?) -> String {
        "\(sessionPid)-\(cwd ?? "")"
    }

    // MARK: - Public API

    /// Check if any terminal window is visible on the current space
    static func isTerminalVisibleOnCurrentSpace() -> Bool {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]

        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        for window in windowList {
            guard let ownerName = window[kCGWindowOwnerName as String] as? String,
                  let layer = window[kCGWindowLayer as String] as? Int,
                  layer == 0 else { continue }

            if TerminalAppRegistry.isTerminal(ownerName) {
                return true
            }
        }

        return false
    }

    /// Check if the frontmost (active) application is a terminal
    static func isTerminalFrontmost() -> Bool {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontmostApp.bundleIdentifier else {
            return false
        }

        return TerminalAppRegistry.isTerminalBundle(bundleId)
    }

    /// Check if a Claude session is currently focused (user is looking at it)
    ///
    /// Two-level check:
    ///   Level 1 (fast, main thread): Is the terminal app frontmost? If NO, return false immediately.
    ///   Level 2 (background): Is the specific session's tab visible?
    ///
    /// - Parameters:
    ///   - sessionPid: The PID of the Claude process
    ///   - cwd: The session's working directory (for tab matching)
    ///   - tty: The session's TTY device (for Terminal.app matching)
    ///   - sessionId: The Claude session ID (for title matching)
    ///   - isInTmux: Whether the session is running inside tmux
    /// - Returns: true if the session's terminal tab is frontmost and visible
    static func isSessionFocused(
        sessionPid: Int,
        cwd: String? = nil,
        tty: String? = nil,
        sessionId: String? = nil,
        isInTmux: Bool = false
    ) async -> Bool {
        // Level 1 (fast): Is any terminal app frontmost?
        guard isTerminalFrontmost() else {
            return false
        }

        // For tmux sessions, use existing tmux pane detection (already accurate)
        if isInTmux {
            return await TmuxTargetFinder.shared.isSessionPaneActive(claudePid: sessionPid)
        }

        // Level 2 (background): Check tab-level focus with caching
        let key = cacheKey(sessionPid: sessionPid, cwd: cwd)
        if let cached = tabFocusCache,
           cached.key == key,
           Date().timeIntervalSince(cached.time) < cacheTTL {
            return cached.result
        }

        let result = await checkTabFocus(
            sessionPid: sessionPid,
            cwd: cwd,
            tty: tty,
            sessionId: sessionId
        )

        tabFocusCache = (key: key, result: result, time: Date())
        return result
    }

    // MARK: - Tab-Level Detection

    /// Dispatch to the appropriate tab checker based on which terminal is frontmost
    private static func checkTabFocus(
        sessionPid: Int,
        cwd: String?,
        tty: String?,
        sessionId: String?
    ) async -> Bool {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontmostApp.bundleIdentifier else {
            return false
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let focused: Bool
                switch bundleId {
                case "com.googlecode.iterm2":
                    focused = checkITerm2Tab(cwd: cwd, sessionId: sessionId)
                case "com.mitchellh.ghostty":
                    focused = checkGhosttyTab(cwd: cwd, sessionId: sessionId)
                case "com.apple.Terminal":
                    focused = checkTerminalAppTab(tty: tty, cwd: cwd)
                case "com.github.wez.wezterm":
                    focused = checkWezTermTab(cwd: cwd)
                case "net.kovidgoyal.kitty":
                    focused = checkKittyTab(cwd: cwd)
                default:
                    // For terminals without tab detection, fall back to process tree check
                    focused = checkFallback(sessionPid: sessionPid)
                }
                continuation.resume(returning: focused)
            }
        }
    }

    // MARK: - Terminal-Specific Tab Checkers

    /// iTerm2: Use AppleScript to get the current session's name and path
    private static func checkITerm2Tab(cwd: String?, sessionId: String?) -> Bool {
        let script = """
        tell application "iTerm2"
            tell current session of current tab of current window
                return name & "|||" & (variable named "session.path")
            end tell
        end tell
        """

        guard let output = runAppleScript(script) else {
            return true // Assume focused if AppleScript fails (app might not be installed/responding)
        }

        let parts = output.components(separatedBy: "|||")
        let sessionName = parts.first ?? ""
        let sessionPath = parts.count > 1 ? parts[1] : ""

        // Match by CWD
        if let cwd = cwd, !cwd.isEmpty, !sessionPath.isEmpty {
            let normalizedCwd = (cwd as NSString).standardizingPath
            let normalizedPath = (sessionPath as NSString).standardizingPath
            if normalizedCwd == normalizedPath {
                return true
            }
        }

        // Match by session ID in the tab name
        if let sessionId = sessionId, !sessionId.isEmpty, sessionName.contains(sessionId) {
            return true
        }

        // Had matching criteria but nothing matched -- different tab is focused
        if cwd != nil || sessionId != nil {
            return false
        }

        return true
    }

    /// Ghostty: Use AppleScript to check the frontmost window title
    private static func checkGhosttyTab(cwd: String?, sessionId: String?) -> Bool {
        let script = """
        tell application "System Events"
            tell process "Ghostty"
                set windowTitle to name of front window
                return windowTitle
            end tell
        end tell
        """

        guard let windowTitle = runAppleScript(script) else {
            return true
        }

        // Ghostty window titles typically contain the CWD or directory name
        if let cwd = cwd, !cwd.isEmpty {
            let dirName = (cwd as NSString).lastPathComponent
            if windowTitle.contains(cwd) || windowTitle.contains(dirName) {
                return true
            }
            return false
        }

        if let sessionId = sessionId, !sessionId.isEmpty, windowTitle.contains(sessionId) {
            return true
        }

        return true
    }

    /// Terminal.app: Use AppleScript to match by TTY or custom title
    private static func checkTerminalAppTab(tty: String?, cwd: String?) -> Bool {
        let script = """
        tell application "Terminal"
            set frontTab to selected tab of front window
            set tabTTY to tty of frontTab
            set tabTitle to custom title of frontTab
            return tabTTY & "|||" & tabTitle
        end tell
        """

        guard let output = runAppleScript(script) else {
            return true
        }

        let parts = output.components(separatedBy: "|||")
        let tabTTY = parts.first ?? ""
        let tabTitle = parts.count > 1 ? parts[1] : ""

        // Match by TTY (most reliable for Terminal.app)
        if let tty = tty, !tty.isEmpty, !tabTTY.isEmpty {
            if tabTTY == tty || tabTTY.hasSuffix(tty) || tty.hasSuffix(tabTTY) {
                return true
            }
            return false
        }

        // Match by CWD in title
        if let cwd = cwd, !cwd.isEmpty, !tabTitle.isEmpty {
            let dirName = (cwd as NSString).lastPathComponent
            if tabTitle.contains(cwd) || tabTitle.contains(dirName) {
                return true
            }
        }

        return true
    }

    /// WezTerm: Use `wezterm cli list --format json` to check active pane CWD
    private static func checkWezTermTab(cwd: String?) -> Bool {
        guard let cwd = cwd, !cwd.isEmpty else {
            return true
        }

        guard let output = runShellCommand("/usr/local/bin/wezterm", args: ["cli", "list", "--format", "json"]) else {
            return true
        }

        guard let data = output.data(using: .utf8),
              let panes = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return true
        }

        let normalizedCwd = (cwd as NSString).standardizingPath
        for pane in panes {
            guard let paneCwd = pane["cwd"] as? String,
                  let isActive = pane["is_active"] as? Bool,
                  isActive else { continue }

            let normalizedPaneCwd = (paneCwd as NSString).standardizingPath
            if normalizedCwd == normalizedPaneCwd {
                return true
            }
        }

        return false
    }

    /// kitty: Use `kitty @ ls` to check focused window/tab CWD
    private static func checkKittyTab(cwd: String?) -> Bool {
        guard let cwd = cwd, !cwd.isEmpty else {
            return true
        }

        guard let output = runShellCommand("/usr/local/bin/kitty", args: ["@", "ls"]) else {
            return true
        }

        guard let data = output.data(using: .utf8),
              let osWindows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return true
        }

        let normalizedCwd = (cwd as NSString).standardizingPath
        for osWindow in osWindows {
            guard let isFocused = osWindow["is_focused"] as? Bool, isFocused,
                  let tabs = osWindow["tabs"] as? [[String: Any]] else { continue }

            for tab in tabs {
                guard let isActive = tab["is_focused"] as? Bool, isActive,
                      let kittyWindows = tab["windows"] as? [[String: Any]] else { continue }

                for kittyWindow in kittyWindows {
                    guard let isFg = kittyWindow["is_focused"] as? Bool, isFg,
                          let procs = kittyWindow["foreground_processes"] as? [[String: Any]] else { continue }

                    for proc in procs {
                        if let procCwd = proc["cwd"] as? String {
                            let normalizedProcCwd = (procCwd as NSString).standardizingPath
                            if normalizedCwd == normalizedProcCwd {
                                return true
                            }
                        }
                    }
                }
            }
        }

        return false
    }

    /// Fallback for unknown terminals: check if the session's terminal PID matches the frontmost app
    private static func checkFallback(sessionPid: Int) -> Bool {
        let tree = ProcessTreeBuilder.shared.buildTree()
        guard let sessionTerminalPid = ProcessTreeBuilder.shared.findTerminalPid(forProcess: sessionPid, tree: tree),
              let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return false
        }
        return sessionTerminalPid == Int(frontmostApp.processIdentifier)
    }

    // MARK: - Process Helpers

    /// Run an AppleScript and return the trimmed output, or nil on failure
    private static func runAppleScript(_ script: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    /// Run a shell command and return the trimmed output, or nil on failure
    private static func runShellCommand(_ command: String, args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
}
