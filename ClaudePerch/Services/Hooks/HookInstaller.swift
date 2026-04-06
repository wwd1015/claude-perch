//
//  HookInstaller.swift
//  ClaudePerch
//
//  Auto-installs Claude Code hooks on app launch
//

import AppKit
import Foundation

struct HookInstaller {

    /// Required hook events that must be registered in settings.json
    private static let requiredHookEvents = [
        "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest",
        "Notification", "Stop", "SubagentStop", "SessionStart", "SessionEnd",
        "PreCompact"
    ]

    /// The hook command that points directly to the bundled Python script
    private static func hookCommand() -> String {
        let scriptPath = Bundle.main.bundlePath + "/Contents/Resources/claude-perch-state.py"
        return "python3 \"\(scriptPath)\""
    }

    /// Verify hooks are up-to-date and repair if stale or missing
    static func verifyAndRepair() {
        let settings = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")

        guard let data = try? Data(contentsOf: settings),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            installIfNeeded()
            return
        }

        let expectedCommand = hookCommand()

        // Check all required events exist and point to the current app location
        for event in requiredHookEvents {
            guard let entries = hooks[event] as? [[String: Any]] else {
                installIfNeeded()
                return
            }

            let hasCorrectHook = entries.contains { entry in
                if let entryHooks = entry["hooks"] as? [[String: Any]] {
                    return entryHooks.contains { h in
                        (h["command"] as? String) == expectedCommand
                    }
                }
                return false
            }

            if !hasCorrectHook {
                installIfNeeded()
                return
            }
        }
    }

    /// Install hooks by registering the bundled script directly in settings.json.
    /// No files are copied — the command points straight to the app bundle.
    static func installIfNeeded() {
        let settings = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")

        // Clean up legacy launcher script if it exists
        let legacyScript = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/hooks/claude-perch-state.py")
        if FileManager.default.fileExists(atPath: legacyScript.path) {
            try? FileManager.default.removeItem(at: legacyScript)
        }

        updateSettings(at: settings)
    }

    /// Completely uninstall Claude Perch: remove hooks, settings entries, and the app itself
    static func selfDelete() {
        // 1. Uninstall hooks from settings.json
        uninstall()

        // 2. Remove legacy hook script if it exists
        let legacyScript = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/hooks/claude-perch-state.py")
        try? FileManager.default.removeItem(at: legacyScript)

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

        let command = hookCommand()
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

        let expectedCommand = hookCommand()

        for (event, config) in hookEvents {
            if var existingEvent = hooks[event] as? [[String: Any]] {
                // Remove any stale claude-perch entries (old launcher or wrong app path)
                existingEvent.removeAll { entry in
                    if let entryHooks = entry["hooks"] as? [[String: Any]] {
                        return entryHooks.contains { h in
                            let cmd = h["command"] as? String ?? ""
                            return cmd.contains("claude-perch") && cmd != expectedCommand
                        }
                    }
                    return false
                }

                let hasCorrectHook = existingEvent.contains { entry in
                    if let entryHooks = entry["hooks"] as? [[String: Any]] {
                        return entryHooks.contains { h in
                            (h["command"] as? String) == expectedCommand
                        }
                    }
                    return false
                }
                if !hasCorrectHook {
                    existingEvent.append(contentsOf: config)
                }
                hooks[event] = existingEvent
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

    /// Uninstall hooks from settings.json and remove legacy script
    static func uninstall() {
        let claudeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
        let settings = claudeDir.appendingPathComponent("settings.json")

        // Clean up legacy launcher script
        let legacyScript = claudeDir.appendingPathComponent("hooks/claude-perch-state.py")
        try? FileManager.default.removeItem(at: legacyScript)

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

}
