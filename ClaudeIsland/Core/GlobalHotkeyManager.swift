//
//  GlobalHotkeyManager.swift
//  ClaudeIsland
//
//  Global keyboard shortcuts for approving/denying permissions.
//  Two tiers:
//    Global (works from any app): Ctrl+Shift+A/D
//    Cmd shortcuts (shown in buttons): Cmd+Y/N for approve/deny, Cmd+1-9 for question options
//

import AppKit
import os.log

private let logger = Logger(subsystem: "com.claudeisland", category: "Hotkeys")

@MainActor
class GlobalHotkeyManager {
    static let shared = GlobalHotkeyManager()

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var approveHandler: (() -> Void)?
    private var denyHandler: (() -> Void)?
    /// Called with option index (0-based) when Cmd+1-9 is pressed
    private var optionHandler: ((Int) -> Void)?

    private init() {}

    /// Start listening for global hotkeys.
    func start(
        onApprove: @escaping () -> Void,
        onDeny: @escaping () -> Void,
        onSelectOption: ((Int) -> Void)? = nil
    ) {
        approveHandler = onApprove
        denyHandler = onDeny
        optionHandler = onSelectOption

        // Global monitor: Ctrl+Shift+A/D (works even when app is not focused)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleGlobalKeyEvent(event)
        }

        // Local monitor: Cmd+Y/N and Cmd+1-9 (works when our window is active)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleLocalKeyEvent(event) == true {
                return nil // Consume the event
            }
            return event
        }

        logger.info("Hotkey monitors started (global: Ctrl+Shift+A/D, local: Cmd+Y/N/1-9)")
    }

    func stop() {
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
    }

    // MARK: - Global: Ctrl+Shift+A/D

    private func handleGlobalKeyEvent(_ event: NSEvent) {
        let requiredFlags: NSEvent.ModifierFlags = [.control, .shift]
        let forbiddenFlags: NSEvent.ModifierFlags = [.command, .option]

        guard event.modifierFlags.contains(requiredFlags),
              !event.modifierFlags.contains(forbiddenFlags) else { return }

        switch event.keyCode {
        case 0:  // 'A' key
            logger.info("Hotkey: Ctrl+Shift+A (approve)")
            Task { @MainActor in self.approveHandler?() }
        case 2:  // 'D' key
            logger.info("Hotkey: Ctrl+Shift+D (deny)")
            Task { @MainActor in self.denyHandler?() }
        default:
            break
        }
    }

    // MARK: - Local: Cmd+Y/N and Cmd+1-9

    /// Returns true if the event was consumed
    private func handleLocalKeyEvent(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else { return false }

        switch event.keyCode {
        case 16:  // 'Y' key
            logger.info("Hotkey: Cmd+Y (allow)")
            approveHandler?()
            return true
        case 45:  // 'N' key
            logger.info("Hotkey: Cmd+N (deny)")
            denyHandler?()
            return true
        default:
            break
        }

        // Cmd+1 through Cmd+9 for question options
        if let chars = event.charactersIgnoringModifiers,
           let digit = chars.first,
           digit >= "1" && digit <= "9" {
            let index = Int(String(digit))! - 1
            logger.info("Hotkey: Cmd+\(index + 1) (select option)")
            optionHandler?(index)
            return true
        }

        return false
    }
}
