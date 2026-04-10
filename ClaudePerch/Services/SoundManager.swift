//
//  SoundManager.swift
//  ClaudePerch
//
//  Plays system sounds for session events.
//  Respects soundEnabled and soundVolume settings with cooldown to prevent rapid-fire.
//

import AppKit
import Foundation
import os.log

/// Sound events that can be triggered by session phase transitions
enum SoundEvent {
    /// A new Claude session has started
    case sessionStart
    /// A permission approval is needed
    case approvalNeeded
    /// A session task completed (went idle/waitingForInput after processing)
    case taskComplete

    /// The system sound name to play
    var soundName: String {
        switch self {
        case .sessionStart: return "Blow"
        case .approvalNeeded: return "Glass"
        case .taskComplete: return "Hero"
        }
    }
}

/// Manages playing system sounds for session events
final class SoundManager: @unchecked Sendable {
    static let shared = SoundManager()

    private static let logger = Logger(subsystem: "com.claudeisland", category: "SoundManager")

    /// Minimum interval between sounds of the same type (seconds)
    private let cooldownInterval: TimeInterval = 2.0

    /// Track last play time per event type to enforce cooldown
    private var lastPlayTimes: [SoundEvent: Date] = [:]

    /// Lock for thread-safe access to lastPlayTimes
    private let lock = NSLock()

    /// Whether the app has finished its initial launch phase
    /// Set to true after a short delay to avoid startup noise
    /// Protected by `lock` for thread safety
    private var hasFinishedLaunching = false

    private init() {
        // Delay enabling sounds to avoid startup noise
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.hasFinishedLaunching = true
            self.lock.unlock()
            Self.logger.debug("SoundManager ready (startup grace period ended)")
        }
    }

    /// Play a sound for the given event, respecting settings and cooldown
    func play(_ event: SoundEvent) {
        lock.lock()
        let launched = hasFinishedLaunching
        lock.unlock()
        guard launched else {
            Self.logger.debug("Skipping sound \(event.soundName, privacy: .public) (startup grace period)")
            return
        }

        guard AppSettings.soundEnabled else { return }

        // Check cooldown
        lock.lock()
        let now = Date()
        if let lastTime = lastPlayTimes[event],
           now.timeIntervalSince(lastTime) < cooldownInterval {
            lock.unlock()
            Self.logger.debug("Skipping sound \(event.soundName, privacy: .public) (cooldown)")
            return
        }
        lastPlayTimes[event] = now
        lock.unlock()

        let volume = AppSettings.soundVolume
        guard volume > 0 else { return }

        // Play on main thread since NSSound requires it
        DispatchQueue.main.async {
            guard let sound = NSSound(named: event.soundName) else {
                Self.logger.warning("System sound not found: \(event.soundName, privacy: .public)")
                return
            }
            sound.volume = volume
            sound.play()
            Self.logger.debug("Played sound: \(event.soundName, privacy: .public) at volume \(volume)")
        }
    }
}

// MARK: - Hashable conformance for SoundEvent (needed for dictionary key)

extension SoundEvent: Hashable {}
