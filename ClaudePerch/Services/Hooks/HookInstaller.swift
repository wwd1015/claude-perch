//
//  HookInstaller.swift
//  ClaudePerch
//
//  Auto-installs Claude Code hooks on app launch
//

import AppKit
import Foundation

struct HookInstaller {

    private static let hookScriptVersion = 1

    /// Required hook events that must be registered in settings.json
    private static let requiredHookEvents = [
        "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest",
        "Notification", "Stop", "SubagentStop", "SessionStart", "SessionEnd",
        "PreCompact"
    ]

    /// Verify hooks are up-to-date and repair if stale or missing
    static func verifyAndRepair() {
        let hooksDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/hooks")
        let launcherPath = hooksDir.appendingPathComponent(launcherName)

        // Check if launcher exists and has correct version
        if FileManager.default.fileExists(atPath: launcherPath.path) {
            if let content = try? String(contentsOf: launcherPath, encoding: .utf8) {
                let expectedMarker = "# HOOK_VERSION=\(hookScriptVersion)"
                if content.contains(expectedMarker) {
                    // Version matches, verify settings.json hooks are registered
                    verifySettingsHooks()
                    return
                }
            }
        }

        // Stale or missing — reinstall
        installIfNeeded()
    }

    /// Verify all required hook events are registered in settings.json
    private static func verifySettingsHooks() {
        let settings = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")

        guard let data = try? Data(contentsOf: settings),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            // No settings or hooks section — reinstall
            installIfNeeded()
            return
        }

        for event in requiredHookEvents {
            guard let entries = hooks[event] as? [[String: Any]] else {
                // Missing event — reinstall
                installIfNeeded()
                return
            }

            let hasOurHook = entries.contains { entry in
                if let entryHooks = entry["hooks"] as? [[String: Any]] {
                    return entryHooks.contains { h in
                        let cmd = h["command"] as? String ?? ""
                        return cmd.contains("claude-perch")
                    }
                }
                return false
            }

            if !hasOurHook {
                // Our hook missing from this event — reinstall
                installIfNeeded()
                return
            }
        }
    }

    /// Path to the launcher script installed in ~/.claude/hooks/
    private static let launcherName = "claude-perch-state.py"

    /// The thin launcher script (like Vibe Island's approach).
    /// Instead of copying 275 lines of Python logic, this tiny script just finds
    /// and executes the real script bundled inside the app.
    private static func launcherScript() -> String {
        let appPath = Bundle.main.bundlePath
        return """
        #!/bin/bash
        # HOOK_VERSION=\(hookScriptVersion)
        # Claude Perch hook launcher (auto-generated, do not edit)
        # The real hook script lives inside the app bundle.
        H="/Contents/Resources/claude-perch-state.py"
        PYTHON="$(command -v python3 2>/dev/null || echo python)"

        # Try known app locations
        for P in "\(appPath)" "/Applications/Claude Perch.app" "$HOME/Applications/Claude Perch.app"; do
          S="${P}${H}"
          [ -f "$S" ] && exec "$PYTHON" "$S" "$@"
        done

        # Fallback: search via mdfind
        P="$(/usr/bin/mdfind 'kMDItemCFBundleIdentifier == "com.claudeperch.app"' 2>/dev/null | /usr/bin/head -1)"
        S="${P}${H}"
        [ -f "$S" ] && exec "$PYTHON" "$S" "$@"

        # Last resort: legacy direct path (if someone copied the script manually)
        [ -f "$HOME/.claude/hooks/claude-perch-state-full.py" ] && exec "$PYTHON" "$HOME/.claude/hooks/claude-perch-state-full.py" "$@"

        exit 0
        """
    }

    /// Install thin launcher script and update settings.json on app launch.
    /// The real logic stays inside the app bundle — only a tiny launcher goes to ~/.claude/hooks/.
    static func installIfNeeded() {
        let claudeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
        let hooksDir = claudeDir.appendingPathComponent("hooks")
        let launcherPath = hooksDir.appendingPathComponent(launcherName)
        let settings = claudeDir.appendingPathComponent("settings.json")

        try? FileManager.default.createDirectory(
            at: hooksDir,
            withIntermediateDirectories: true
        )

        // Write the thin launcher script
        let launcher = launcherScript()
        try? launcher.write(to: launcherPath, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: launcherPath.path
        )

        updateSettings(at: settings)
    }

    /// Completely uninstall Claude Perch: remove hooks, settings entries, and the app itself
    static func selfDelete() {
        // 1. Uninstall hooks from settings.json
        uninstall()

        // 2. Remove the hook script
        let hooksDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/hooks")
        try? FileManager.default.removeItem(at: hooksDir.appendingPathComponent("claude-perch-state.py"))

        // 3. Remove the socket
        unlink("/tmp/claude-perch.sock")

        // 4. Move the app to trash
        if let appURL = Bundle.main.bundleURL as NSURL? {
            // Use NSWorkspace to move to trash (recoverable)
            NSWorkspace.shared.recycle([appURL as URL]) { trashedURLs, error in
                if error != nil {
                    // Fallback: try direct delete
                    try? FileManager.default.removeItem(at: appURL as URL)
                }
                // 5. Quit the app
                DispatchQueue.main.async {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }

    private static func updateSettings(at settingsURL: URL) {
        var json: [String: Any] = [:]
        if let data = try? Data(contentsOf: settingsURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = existing
        }

        let command = "bash ~/.claude/hooks/\(launcherName)"
        let hookEntry: [[String: Any]] = [["type": "command", "command": command]]
        let hookEntryWithTimeout: [[String: Any]] = [["type": "command", "command": command, "timeout": 86400]]
        let withMatcher: [[String: Any]] = [["matcher": "*", "hooks": hookEntry]]
        let withMatcherAndTimeout: [[String: Any]] = [["matcher": "*", "hooks": hookEntryWithTimeout]]
        let withoutMatcher: [[String: Any]] = [["hooks": hookEntry]]
        let preCompactConfig: [[String: Any]] = [
            ["matcher": "auto", "hooks": hookEntry],
            ["matcher": "manual", "hooks": hookEntry]
        ]

        var hooks = json["hooks"] as? [String: Any] ?? [:]

        let hookEvents: [(String, [[String: Any]])] = [
            ("UserPromptSubmit", withoutMatcher),
            ("PreToolUse", withMatcher),
            ("PostToolUse", withMatcher),
            ("PermissionRequest", withMatcherAndTimeout),
            ("Notification", withMatcher),
            ("Stop", withoutMatcher),
            ("SubagentStop", withoutMatcher),
            ("SessionStart", withoutMatcher),
            ("SessionEnd", withoutMatcher),
            ("PreCompact", preCompactConfig),
        ]

        for (event, config) in hookEvents {
            if var existingEvent = hooks[event] as? [[String: Any]] {
                let hasOurHook = existingEvent.contains { entry in
                    if let entryHooks = entry["hooks"] as? [[String: Any]] {
                        return entryHooks.contains { h in
                            let cmd = h["command"] as? String ?? ""
                            return cmd.contains("claude-perch")
                        }
                    }
                    return false
                }
                if !hasOurHook {
                    existingEvent.append(contentsOf: config)
                    hooks[event] = existingEvent
                }
            } else {
                hooks[event] = config
            }
        }

        json["hooks"] = hooks

        if let data = try? JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            try? data.write(to: settingsURL)
        }
    }

    /// Check if hooks are currently installed
    static func isInstalled() -> Bool {
        let claudeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
        let settings = claudeDir.appendingPathComponent("settings.json")

        guard let data = try? Data(contentsOf: settings),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            return false
        }

        for (_, value) in hooks {
            if let entries = value as? [[String: Any]] {
                for entry in entries {
                    if let entryHooks = entry["hooks"] as? [[String: Any]] {
                        for hook in entryHooks {
                            if let cmd = hook["command"] as? String,
                               cmd.contains("claude-perch") {
                                return true
                            }
                        }
                    }
                }
            }
        }
        return false
    }

    /// Uninstall hooks from settings.json and remove script
    static func uninstall() {
        let claudeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
        let hooksDir = claudeDir.appendingPathComponent("hooks")
        let pythonScript = hooksDir.appendingPathComponent("claude-perch-state.py")
        let settings = claudeDir.appendingPathComponent("settings.json")

        try? FileManager.default.removeItem(at: pythonScript)

        guard let data = try? Data(contentsOf: settings),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = json["hooks"] as? [String: Any] else {
            return
        }

        for (event, value) in hooks {
            if var entries = value as? [[String: Any]] {
                entries.removeAll { entry in
                    if let entryHooks = entry["hooks"] as? [[String: Any]] {
                        return entryHooks.contains { hook in
                            let cmd = hook["command"] as? String ?? ""
                            return cmd.contains("claude-perch")
                        }
                    }
                    return false
                }

                if entries.isEmpty {
                    hooks.removeValue(forKey: event)
                } else {
                    hooks[event] = entries
                }
            }
        }

        if hooks.isEmpty {
            json.removeValue(forKey: "hooks")
        } else {
            json["hooks"] = hooks
        }

        if let data = try? JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            try? data.write(to: settings)
        }
    }

    // Python detection is now handled by the launcher script itself
}
