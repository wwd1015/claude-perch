//
//  GlobalHotkeyManager.swift
//  ClaudeIsland
//
//  Global keyboard shortcuts matching Vibe Island:
//  ^G = Toggle panel (open/close notch from anywhere)
//  ^Y = Approve    ^N = Deny
//  ^A = Always Allow    ^B = Bypass Permissions
//  ^T = Jump to Terminal
//  ^1-9 = Select question option
//

import AppKit
import os.log

private let logger = Logger(subsystem: "com.claudeisland", category: "Hotkeys")

@MainActor
class GlobalHotkeyManager {
    static let shared = GlobalHotkeyManager()

    private var globalMonitor: Any?
    private var localMonitor: Any?

    // Callbacks
    var onTogglePanel: (() -> Void)?
    var onApprove: (() -> Void)?
    var onDeny: (() -> Void)?
    var onAlwaysAllow: (() -> Void)?
    var onBypass: (() -> Void)?
    var onJumpToTerminal: (() -> Void)?
    var onSelectOption: ((Int) -> Void)?

    private init() {}

    func start() {
        // Global monitor: works even when app is not focused
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }

        // Local monitor: works when our window is active
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleKeyEvent(event) == true {
                return nil // Consume the event
            }
            return event
        }

        logger.info("Hotkey monitors started (^G/Y/N/A/B/T/1-9)")
    }

    func stop() {
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
    }

    /// Handle a key event. Returns true if consumed.
    @discardableResult
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        // Require Control key, no Cmd or Option
        guard event.modifierFlags.contains(.control),
              !event.modifierFlags.contains(.command),
              !event.modifierFlags.contains(.option) else { return false }

        switch event.keyCode {
        case 5:  // 'G' key - Toggle panel
            logger.info("Hotkey: ^G (toggle panel)")
            Task { @MainActor in self.onTogglePanel?() }
            return true

        case 16: // 'Y' key - Approve
            logger.info("Hotkey: ^Y (approve)")
            Task { @MainActor in self.onApprove?() }
            return true

        case 45: // 'N' key - Deny
            logger.info("Hotkey: ^N (deny)")
            Task { @MainActor in self.onDeny?() }
            return true

        case 0:  // 'A' key - Always Allow
            logger.info("Hotkey: ^A (always allow)")
            Task { @MainActor in self.onAlwaysAllow?() }
            return true

        case 11: // 'B' key - Bypass
            logger.info("Hotkey: ^B (bypass)")
            Task { @MainActor in self.onBypass?() }
            return true

        case 17: // 'T' key - Jump to Terminal
            logger.info("Hotkey: ^T (jump to terminal)")
            Task { @MainActor in self.onJumpToTerminal?() }
            return true

        default:
            break
        }

        // ^1 through ^9 for question options
        if let chars = event.charactersIgnoringModifiers,
           let digit = chars.first,
           digit >= "1" && digit <= "9" {
            let index = Int(String(digit))! - 1
            logger.info("Hotkey: ^\(index + 1) (select option)")
            Task { @MainActor in self.onSelectOption?(index) }
            return true
        }

        return false
    }
}
