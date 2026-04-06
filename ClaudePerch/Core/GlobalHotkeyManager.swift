//
//  GlobalHotkeyManager.swift
//  ClaudePerch
//
//  Global keyboard shortcuts using CGEvent tap (reliable from any app):
//  ^G = Toggle panel    ^Y = Approve    ^N = Deny
//  ^A = Always Allow    ^B = Bypass     ^T = Jump to Terminal
//  ^1-9 = Select question option
//

import AppKit
import os.log

private let logger = Logger(subsystem: "com.claudeperch", category: "Hotkeys")

@MainActor
class GlobalHotkeyManager {
    static let shared = GlobalHotkeyManager()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
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
        // Request Accessibility permission if not granted
        if !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
            logger.warning("Accessibility not granted — prompting user.")
        }

        setupEventTap()

        // Local monitor for when our own windows are focused
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleKey(event) == true {
                return nil
            }
            return event
        }

        logger.info("Hotkey manager started (accessibility: \(AXIsProcessTrusted()))")
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
        }
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
    }

    // MARK: - CGEvent Tap (works globally)

    private func setupEventTap() {
        // Store self pointer for the C callback
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,  // Don't consume events, just observe
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(refcon).takeUnretainedValue()

                // Check for Control modifier (no Cmd, no Option)
                let flags = event.flags
                guard flags.contains(.maskControl),
                      !flags.contains(.maskCommand),
                      !flags.contains(.maskAlternate) else {
                    return Unmanaged.passRetained(event)
                }

                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

                DispatchQueue.main.async {
                    manager.handleKeyCode(Int(keyCode))
                }

                return Unmanaged.passRetained(event)
            },
            userInfo: refcon
        ) else {
            logger.error("Failed to create CGEvent tap — Accessibility permission may be missing")
            // Fall back to NSEvent global monitor
            setupFallbackMonitor()
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        logger.info("CGEvent tap created successfully")
    }

    /// Fallback if CGEvent tap fails (e.g., no Accessibility yet)
    private func setupFallbackMonitor() {
        let monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event)
        }
        // Store in localMonitor slot (we only use one or the other)
        if localMonitor == nil {
            localMonitor = monitor
        }
        logger.info("Using NSEvent fallback monitor")
    }

    // MARK: - Key Handling

    private func handleKeyCode(_ keyCode: Int) {
        switch keyCode {
        case 5:  // G
            logger.info("Hotkey: ^G (toggle panel)")
            onTogglePanel?()
        case 16: // Y
            logger.info("Hotkey: ^Y (approve)")
            onApprove?()
        case 45: // N
            logger.info("Hotkey: ^N (deny)")
            onDeny?()
        case 0:  // A
            logger.info("Hotkey: ^A (always allow)")
            onAlwaysAllow?()
        case 11: // B
            logger.info("Hotkey: ^B (bypass)")
            onBypass?()
        case 17: // T
            logger.info("Hotkey: ^T (jump to terminal)")
            onJumpToTerminal?()
        case 18: // 1
            onSelectOption?(0)
        case 19: // 2
            onSelectOption?(1)
        case 20: // 3
            onSelectOption?(2)
        case 21: // 4
            onSelectOption?(3)
        case 23: // 5
            onSelectOption?(4)
        case 22: // 6
            onSelectOption?(5)
        case 26: // 7
            onSelectOption?(6)
        case 28: // 8
            onSelectOption?(7)
        case 25: // 9
            onSelectOption?(8)
        default:
            break
        }
    }

    /// Handle NSEvent (for local monitor and fallback)
    @discardableResult
    private func handleKey(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.control),
              !event.modifierFlags.contains(.command),
              !event.modifierFlags.contains(.option) else { return false }

        let keyCode = Int(event.keyCode)

        switch keyCode {
        case 5, 16, 45, 0, 11, 17, 18, 19, 20, 21, 22, 23, 25, 26, 28:
            handleKeyCode(keyCode)
            return true
        default:
            return false
        }
    }
}
