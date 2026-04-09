//
//  Settings.swift
//  ClaudePerch
//
//  App settings manager using UserDefaults
//

import Foundation

/// Available notification sounds
enum NotificationSound: String, CaseIterable {
    case none = "None"
    case pop = "Pop"
    case ping = "Ping"
    case tink = "Tink"
    case glass = "Glass"
    case blow = "Blow"
    case bottle = "Bottle"
    case frog = "Frog"
    case funk = "Funk"
    case hero = "Hero"
    case morse = "Morse"
    case purr = "Purr"
    case sosumi = "Sosumi"
    case submarine = "Submarine"
    case basso = "Basso"

    /// The system sound name to use with NSSound, or nil for no sound
    var soundName: String? {
        self == .none ? nil : rawValue
    }
}

enum AppSettings {
    private static let defaults = UserDefaults.standard

    // MARK: - Keys

    private enum Keys {
        static let notificationSound = "notificationSound"
        static let urgentNotificationSound = "urgentNotificationSound"
        static let soundEnabled = "soundEnabled"
        static let soundVolume = "soundVolume"
        static let claudeConfigPath = "claudeConfigPath"
    }

    // MARK: - Sound Settings

    /// Master toggle for sound effects (opt-in, default false)
    static var soundEnabled: Bool {
        get {
            if defaults.object(forKey: Keys.soundEnabled) == nil {
                return false
            }
            return defaults.bool(forKey: Keys.soundEnabled)
        }
        set {
            defaults.set(newValue, forKey: Keys.soundEnabled)
        }
    }

    /// Sound volume from 0.0 to 1.0 (default 0.5)
    static var soundVolume: Float {
        get {
            let value = defaults.float(forKey: Keys.soundVolume)
            if defaults.object(forKey: Keys.soundVolume) == nil {
                return 0.5
            }
            return max(0.0, min(1.0, value))
        }
        set {
            defaults.set(max(0.0, min(1.0, newValue)), forKey: Keys.soundVolume)
        }
    }

    // MARK: - Claude Config Path

    static let defaultClaudeConfigPath = "~/.claude"

    /// The raw config path as stored (may contain ~)
    static var claudeConfigPath: String {
        get {
            defaults.string(forKey: Keys.claudeConfigPath) ?? defaultClaudeConfigPath
        }
        set {
            defaults.set(newValue, forKey: Keys.claudeConfigPath)
        }
    }

    /// The resolved absolute path (~ expanded)
    static var resolvedClaudeConfigPath: String {
        (claudeConfigPath as NSString).expandingTildeInPath
    }

    /// URL for the Claude config directory
    static var claudeConfigURL: URL {
        URL(fileURLWithPath: resolvedClaudeConfigPath)
    }

    /// Path to settings.json inside the Claude config directory
    static var claudeSettingsURL: URL {
        claudeConfigURL.appendingPathComponent("settings.json")
    }

    /// Path to the projects directory inside the Claude config directory
    static var claudeProjectsPath: String {
        resolvedClaudeConfigPath + "/projects"
    }

    /// Path to the legacy hooks directory
    static var claudeHooksPath: String {
        resolvedClaudeConfigPath + "/hooks"
    }

    /// Reset the config path to default
    static func resetClaudeConfigPath() {
        defaults.removeObject(forKey: Keys.claudeConfigPath)
    }

    /// Validate that a path looks like a valid Claude config directory
    static func validateClaudeConfigPath(_ path: String) -> (isValid: Bool, message: String) {
        let resolved = (path as NSString).expandingTildeInPath
        let fm = FileManager.default
        var isDir: ObjCBool = false

        guard fm.fileExists(atPath: resolved, isDirectory: &isDir), isDir.boolValue else {
            return (false, "Directory does not exist")
        }

        let settingsFile = resolved + "/settings.json"
        if fm.fileExists(atPath: settingsFile) {
            return (true, "Valid Claude config directory")
        } else {
            return (true, "Directory exists but settings.json not found (hooks will be created)")
        }
    }

    // MARK: - Notification Sounds (two-tier)

    /// Info-tier sound: played when Claude finishes and is ready for input
    static var notificationSound: NotificationSound {
        get {
            guard let rawValue = defaults.string(forKey: Keys.notificationSound),
                  let sound = NotificationSound(rawValue: rawValue) else {
                return .pop // Default to Pop
            }
            return sound
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.notificationSound)
        }
    }

    /// Urgent-tier sound: played when a permission request needs approval
    static var urgentNotificationSound: NotificationSound {
        get {
            guard let rawValue = defaults.string(forKey: Keys.urgentNotificationSound),
                  let sound = NotificationSound(rawValue: rawValue) else {
                return .glass // Default to Glass (more attention-grabbing than Pop)
            }
            return sound
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.urgentNotificationSound)
        }
    }
}
