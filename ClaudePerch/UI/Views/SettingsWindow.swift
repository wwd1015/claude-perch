//
//  SettingsWindow.swift
//  ClaudePerch
//
//  Settings window with sidebar navigation.
//

import SwiftUI
import ServiceManagement

// MARK: - Settings Tab

enum SettingsTab: String, CaseIterable {
    case general = "General"
    case display = "Display"
    case sound = "Sound"
    case shortcuts = "Shortcuts"
    case about = "About"

    var icon: String {
        switch self {
        case .general: return "gear"
        case .display: return "textformat.size"
        case .sound: return "speaker.wave.2.fill"
        case .shortcuts: return "keyboard"
        case .about: return "info.circle"
        }
    }

    var iconColor: Color {
        switch self {
        case .general: return Color(red: 0.4, green: 0.5, blue: 0.9)
        case .display: return Color(red: 0.3, green: 0.8, blue: 0.5)
        case .sound: return Color(red: 0.9, green: 0.5, blue: 0.3)
        case .shortcuts: return Color(red: 0.5, green: 0.5, blue: 0.8)
        case .about: return Color(red: 0.4, green: 0.6, blue: 0.9)
        }
    }
}

// MARK: - Settings Window

struct SettingsWindowView: View {
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(SettingsTab.allCases, id: \.self, selection: $selectedTab) { tab in
                Label {
                    Text(tab.rawValue)
                        .font(.system(size: 13))
                } icon: {
                    Image(systemName: tab.icon)
                        .font(.system(size: 11))
                        .foregroundColor(.white)
                        .frame(width: 24, height: 24)
                        .background(tab.iconColor)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)
        } detail: {
            switch selectedTab {
            case .general:
                GeneralSettingsView()
            case .display:
                DisplaySettingsView()
            case .sound:
                SoundSettingsView()
            case .shortcuts:
                ShortcutsSettingsView()
            case .about:
                AboutSettingsView()
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(width: 650, height: 500)
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var hooksInstalled = HookInstaller.isInstalled()
    @AppStorage("hideInFullscreen") private var hideInFullscreen = true
    @AppStorage("autoHideNoSessions") private var autoHideNoSessions = false
    @AppStorage("smartSuppression") private var smartSuppression = true
    @AppStorage("autoCollapse") private var autoCollapse = true
    @AppStorage("showUsage") private var showUsage = false
    @State private var showUninstallConfirmation = false

    var body: some View {
        Form {
            Section("System") {
                Toggle("Launch at Login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                            launchAtLogin = newValue
                        } catch {
                            print("Failed to toggle launch at login: \(error)")
                        }
                    }
                ))

                HStack {
                    Text("Hooks")
                    Spacer()
                    if hooksInstalled {
                        Label("Installed", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    } else {
                        Button("Install") {
                            HookInstaller.installIfNeeded()
                            hooksInstalled = true
                        }
                    }
                }

                HStack {
                    Text("Display")
                    Spacer()
                    Text("Automatic")
                        .foregroundColor(.secondary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            Section("Behaviour") {
                Toggle("Hide in fullscreen", isOn: $hideInFullscreen)

                Toggle("Auto-hide when no active sessions", isOn: $autoHideNoSessions)

                Toggle(isOn: $smartSuppression) {
                    VStack(alignment: .leading) {
                        Text("Smart suppression")
                        Text("Don't auto-expand when the agent's terminal tab is in focus")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Toggle("Auto-collapse on mouse leave", isOn: $autoCollapse)

                Toggle(isOn: $showUsage) {
                    VStack(alignment: .leading) {
                        Text("Show Usage")
                        Text("Display API usage data in the notch panel header")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section("Danger Zone") {
                Button(role: .destructive) {
                    showUninstallConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("Uninstall Claude Perch")
                    }
                    .foregroundColor(.red)
                }
                .alert("Uninstall Claude Perch?", isPresented: $showUninstallConfirmation) {
                    Button("Cancel", role: .cancel) {}
                    Button("Uninstall", role: .destructive) {
                        HookInstaller.selfDelete()
                    }
                } message: {
                    Text("This will remove all hooks from settings.json, delete the hook script, and move the app to Trash.")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }
}

// MARK: - Display Settings

struct DisplaySettingsView: View {
    @ObservedObject private var screenSelector = ScreenSelector.shared
    @AppStorage("showActivityLog") private var showActivityLog = true
    @AppStorage("showConversation") private var showConversation = true
    @AppStorage("maxStatusDots") private var maxStatusDots = 8

    var body: some View {
        Form {
            Section("Screen") {
                ScreenPickerRow(screenSelector: screenSelector)
            }

            Section("Notch Panel") {
                Toggle("Show activity log", isOn: $showActivityLog)
                Toggle("Show conversation preview", isOn: $showConversation)
                Stepper("Max status dots: \(maxStatusDots)", value: $maxStatusDots, in: 4...12)
            }

            Section("Session Cards") {
                @AppStorage("showTerminalBadge") var showTerminalBadge = true
                @AppStorage("showTimeActive") var showTimeActive = true
                @AppStorage("showAgentBadge") var showAgentBadge = true
                Toggle("Show terminal badge", isOn: $showTerminalBadge)
                Toggle("Show time active", isOn: $showTimeActive)
                Toggle("Show agent badge", isOn: $showAgentBadge)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Display")
        .preferredColorScheme(.dark)
    }
}

// MARK: - Sound Settings

struct SoundSettingsView: View {
    @AppStorage("soundEnabled") private var soundEnabled = false
    @AppStorage("soundVolume") private var soundVolume: Double = 0.5

    var body: some View {
        Form {
            Section {
                Toggle("Enable Sound Effects", isOn: $soundEnabled)

                HStack {
                    Text("Volume")
                    Image(systemName: "speaker.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Slider(value: $soundVolume, in: 0...1)
                        .disabled(!soundEnabled)
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text("\(Int(soundVolume * 100))%")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 36)
                }
            }

            Section("Events") {
                SoundEventPreviewRow(
                    label: "Session Start",
                    description: "New Claude session begins",
                    soundName: SoundEvent.sessionStart.soundName,
                    volume: Float(soundVolume),
                    enabled: soundEnabled
                )
                SoundEventPreviewRow(
                    label: "Approval Needed",
                    description: "Permission request needs your attention",
                    soundName: SoundEvent.approvalNeeded.soundName,
                    volume: Float(soundVolume),
                    enabled: soundEnabled
                )
                SoundEventPreviewRow(
                    label: "Task Complete",
                    description: "Session finished processing",
                    soundName: SoundEvent.taskComplete.soundName,
                    volume: Float(soundVolume),
                    enabled: soundEnabled
                )
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Sound")
    }
}

struct SoundEventPreviewRow: View {
    let label: String
    let description: String
    let soundName: String
    let volume: Float
    let enabled: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text(soundName)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Button {
                if let sound = NSSound(named: soundName) {
                    sound.volume = volume
                    sound.play()
                }
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(enabled ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
        }
    }
}

// MARK: - Shortcuts Settings

struct ShortcutsSettingsView: View {
    var body: some View {
        Form {
            Section("Modifier Key") {
                HStack {
                    Text("Modifier Key")
                    Spacer()
                    Text("⌃ Control")
                        .foregroundColor(.secondary)
                }
            }

            Section("Global Shortcuts") {
                ShortcutRow(label: "Toggle Panel", description: "Open from anywhere, ↑↓ navigate, Enter jump", shortcut: "⌃G")
            }

            Section("Panel Shortcuts") {
                ShortcutRow(label: "Approve", shortcut: "⌃Y")
                ShortcutRow(label: "Deny", shortcut: "⌃N")
                ShortcutRow(label: "Always Allow", shortcut: "⌃A")
                ShortcutRow(label: "Bypass Permissions", shortcut: "⌃B")
                ShortcutRow(label: "Jump to Terminal", shortcut: "⌃T")
                ShortcutRow(label: "Select Option", shortcut: "⌃1-9")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Shortcuts")
    }
}

struct ShortcutRow: View {
    let label: String
    var description: String? = nil
    let shortcut: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                if let desc = description {
                    Text(desc)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Text(shortcut)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
    }
}

// MARK: - About Settings

struct AboutSettingsView: View {
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "v\(version) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 12) {
                    Text("Claude Perch")
                        .font(.title2.bold())
                    Text(appVersion)
                        .foregroundColor(.secondary)
                    Text("Mission Control for your AI agents")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }

            Section {
                Link("GitHub Repository", destination: URL(string: "https://github.com/wwd1015/claude-perch")!)

                HStack {
                    Text("Accessibility")
                    Spacer()
                    if AXIsProcessTrusted() {
                        Label("Enabled", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    } else {
                        Button("Enable") {
                            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
                            AXIsProcessTrustedWithOptions(options)
                        }
                    }
                }

                HStack {
                    Text("Originally based on")
                    Spacer()
                    Link("Claude Island by Farouq Aldori", destination: URL(string: "https://github.com/farouqaldori/claude-island")!)
                        .font(.caption)
                }
            }

            Section {
                Button("Quit Claude Perch") {
                    NSApplication.shared.terminate(nil)
                }
                .foregroundColor(.red)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("About")
    }
}

// MARK: - Settings Window Controller

class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func showSettings() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsWindowView()
        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 650, height: 500),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Claude Perch Settings"
        window.contentViewController = hostingController
        // Position below the notch area so the title bar is accessible
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 325
            let y = screenFrame.midY - 150
            window.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        window.isReleasedWhenClosed = false
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }
}
