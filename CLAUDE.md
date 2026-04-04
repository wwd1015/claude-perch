# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Build for development (Xcode)
xcodebuild -scheme ClaudePerch -configuration Debug build

# Build release archive + export DMG
./scripts/build.sh

# Notarize and create release DMG
./scripts/create-release.sh
```

Open `ClaudePerch.xcodeproj` in Xcode for development. No package manager step needed — dependencies (Sparkle, Mixpanel) are embedded in the project.

## What This App Does

Claude Perch is a macOS menu bar app that overlays a Dynamic Island-style notch UI on the MacBook notch. It monitors Claude Code CLI sessions in real-time and lets users approve/deny tool permissions without switching to the terminal.

## Architecture

### Data Flow

```
Claude Code CLI → Python hook script → Unix socket → HookSocketServer → SessionStore → ClaudeSessionMonitor → NotchView
```

For permission requests, the flow is bidirectional — the Python hook blocks on the socket waiting for an approve/deny response from the app.

### Core Layers

**Hook System** (`Services/Hooks/`)
- `HookInstaller` — auto-installs `claude-perch-state.py` into `~/.claude/hooks/` and registers hook events in Claude Code's settings.json
- `HookSocketServer` — Unix domain socket server at `/tmp/claude-perch.sock`. Receives `HookEvent` JSON, sends `HookResponse` back for permission decisions. Uses DispatchSource for non-blocking I/O.

**State Management** (`Services/State/`, `Services/Session/`)
- `SessionStore` — Swift actor, single source of truth. All mutations flow through `process(event: SessionEvent)`. Publishes state via Combine.
- `ClaudeSessionMonitor` — MainActor wrapper that bridges SessionStore to SwiftUI
- `ConversationParser` — incremental JSONL parser (reads only new lines since last sync)
- `JSONLInterruptWatcher` — real-time file monitoring for interrupt detection
- `AgentFileWatcher` — monitors subagent JSONL files for Task tool tracking
- `FileSyncScheduler` — debounces JSONL file reads (100ms)

**Session Models** (`Models/`)
- `SessionPhase` — state machine: idle → processing → waitingForInput/waitingForApproval/compacting → ended. Validates all transitions.
- `SessionState` — unified session data: identity, phase, chat history, tool tracking, subagent state
- `SessionEvent` — enum of all mutation events (hook events, permission actions, file updates, etc.)

**Notch UI** (`UI/`)
- `NotchWindow` — NSPanel that floats above menu bar, non-activating, with selective click-through (re-posts mouse events to windows behind)
- `NotchViewController` — hosts SwiftUI in AppKit with custom hit-testing based on panel state
- `NotchViewModel` — manages open/close state, content type (instances/menu/chat), hover detection, dynamic sizing
- `NotchView` — main SwiftUI view observing ClaudeSessionMonitor

**Tmux Integration** (`Services/Tmux/`)
- `TmuxTargetFinder` — finds tmux pane matching a Claude process (by PID or cwd)
- `TmuxSessionMatcher` — matches panes to sessions by content sampling and scoring against JSONL
- `ToolApprovalHandler` — sends tmux key sequences for terminal-based approval (sends "1"/"2"/"n" + Enter)

### Permission Approval Flow

1. Claude Code fires `PermissionRequest` hook → Python script sends event via socket and **blocks**
2. `HookSocketServer` receives event, correlates tool_use_id from cached `PreToolUse` events
3. `SessionStore` transitions to `waitingForApproval` → notch expands with approve/deny UI
4. User clicks button → `SessionStore.approvePermission()` → `HookSocketServer.respondToPermission()` writes response to socket
5. Python script unblocks, outputs decision in Claude Code hook format
6. Stale permissions auto-cleaned every 30s (300s timeout, matching Python hook)

### App Lifecycle

- `ClaudePerchApp` — SwiftUI entry point with NSApplicationDelegateAdaptor
- `AppDelegate` — single instance enforcement, Sparkle auto-updates (1hr interval), Mixpanel analytics, notch window setup
- `ScreenObserver` / `WindowManager` — monitor display changes, recreate window on screen change

## Skill routing

When the user's request matches an available skill, ALWAYS invoke it using the Skill
tool as your FIRST action. Do NOT answer directly, do NOT use other tools first.
The skill has specialized workflows that produce better results than ad-hoc answers.

Key routing rules:
- Product ideas, "is this worth building", brainstorming → invoke office-hours
- Bugs, errors, "why is this broken", 500 errors → invoke investigate
- Ship, deploy, push, create PR → invoke ship
- QA, test the site, find bugs → invoke qa
- Code review, check my diff → invoke review
- Update docs after shipping → invoke document-release
- Weekly retro → invoke retro
- Design system, brand → invoke design-consultation
- Visual audit, design polish → invoke design-review
- Architecture review → invoke plan-eng-review
- Save progress, checkpoint, resume → invoke checkpoint
- Code quality, health check → invoke health
