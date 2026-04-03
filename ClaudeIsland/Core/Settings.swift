//
//  Settings.swift
//  ClaudeIsland
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
