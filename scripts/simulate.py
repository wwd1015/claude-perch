#!/usr/bin/env python3
"""
Simulate Claude Perch hook events for UI testing.

Usage:
  python3 scripts/simulate.py approval       # Normal permission (Deny / Allow / Always Allow)
  python3 scripts/simulate.py bash           # Bash command approval
  python3 scripts/simulate.py edit           # File edit approval
  python3 scripts/simulate.py question       # AskUserQuestion with options
  python3 scripts/simulate.py done           # Task complete (Ready state)
  python3 scripts/simulate.py processing     # Processing state (spinner)
  python3 scripts/simulate.py all            # Run all scenarios sequentially
"""
import json
import os
import socket
import sys
import time
import uuid
import threading

SOCKET_PATH = "/tmp/claude-perch.sock"
SESSION_ID = f"sim-{uuid.uuid4().hex[:8]}"
CWD = os.getcwd()
PID = os.getpid()


def send_event(state, wait_response=False):
    """Send event to Claude Perch app via Unix socket."""
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(300)
        sock.connect(SOCKET_PATH)
        sock.sendall(json.dumps(state).encode())

        if wait_response:
            print("  ⏳ Waiting for response from app...")
            response = sock.recv(4096)
            sock.close()
            if response:
                result = json.loads(response.decode())
                print(f"  ✅ Response: {json.dumps(result, indent=2)}")
                return result
        else:
            sock.close()

        return None
    except FileNotFoundError:
        print("  ❌ Socket not found. Is Claude Perch running?")
        sys.exit(1)
    except (socket.error, OSError) as e:
        print(f"  ❌ Socket error: {e}")
        return None


def base_event(**kwargs):
    """Create base event dict."""
    event = {
        "session_id": SESSION_ID,
        "cwd": CWD,
        "pid": PID,
        "tty": None,
        "term_bundle_id": os.environ.get("__CFBundleIdentifier", ""),
        "tmux_env": os.environ.get("TMUX", ""),
        "tmux_pane": os.environ.get("TMUX_PANE", ""),
    }
    event.update(kwargs)
    return event


def sim_session_start():
    """Start a fake session."""
    print("\n📡 Starting simulated session...")
    send_event(base_event(
        event="SessionStart",
        status="waiting_for_input",
    ))
    time.sleep(0.5)


def sim_processing():
    """Simulate processing state (spinner in notch)."""
    print("\n⚙️  Simulating: Processing state")
    send_event(base_event(
        event="UserPromptSubmit",
        status="processing",
    ))
    print("  → Notch should show processing spinner")
    print("  Press Enter to continue...")
    input()


def sim_done():
    """Simulate task complete (Ready/Done state)."""
    print("\n✅ Simulating: Done / Ready state")
    send_event(base_event(
        event="Stop",
        status="waiting_for_input",
    ))
    print("  → Notch should show green checkmark + 'Ready' text")
    print("  Press Enter to continue...")
    input()


def sim_approval_bash():
    """Simulate Bash command permission request."""
    print("\n🔒 Simulating: Bash command approval")
    print("  → Shows: $ npm install && npm run build")

    # First send PreToolUse to cache the tool_use_id
    tool_use_id = f"tu_{uuid.uuid4().hex[:12]}"
    send_event(base_event(
        event="PreToolUse",
        status="running_tool",
        tool="Bash",
        tool_input={"command": "npm install && npm run build"},
        tool_use_id=tool_use_id,
    ))
    time.sleep(0.3)

    # Then send PermissionRequest (blocks until user responds)
    response = send_event(base_event(
        event="PermissionRequest",
        status="waiting_for_approval",
        tool="Bash",
        tool_input={"command": "npm install && npm run build"},
    ), wait_response=True)

    if response:
        decision = response.get("decision", "none")
        print(f"  → User chose: {decision}")
    print()


def sim_approval_edit():
    """Simulate file Edit permission request."""
    print("\n📝 Simulating: File edit approval")
    print("  → Shows: Edit src/auth/middleware.ts with diff view")

    tool_use_id = f"tu_{uuid.uuid4().hex[:12]}"
    send_event(base_event(
        event="PreToolUse",
        status="running_tool",
        tool="Edit",
        tool_input={
            "file_path": "src/auth/middleware.ts",
            "old_string": "if (token.expired) {\n  return res.status(401).json({ error: 'Token expired' });\n}",
            "new_string": "if (token.expired) {\n  await refreshToken(token);\n  return res.status(401).json({ error: 'Token expired, refreshing...' });\n}",
        },
        tool_use_id=tool_use_id,
    ))
    time.sleep(0.3)

    response = send_event(base_event(
        event="PermissionRequest",
        status="waiting_for_approval",
        tool="Edit",
        tool_input={
            "file_path": "src/auth/middleware.ts",
            "old_string": "if (token.expired) {\n  return res.status(401).json({ error: 'Token expired' });\n}",
            "new_string": "if (token.expired) {\n  await refreshToken(token);\n  return res.status(401).json({ error: 'Token expired, refreshing...' });\n}",
        },
    ), wait_response=True)

    if response:
        decision = response.get("decision", "none")
        print(f"  → User chose: {decision}")
    print()


def sim_approval_generic():
    """Simulate a generic tool permission request (Write)."""
    print("\n📄 Simulating: Write file approval")
    print("  → Shows: Write config.json")

    tool_use_id = f"tu_{uuid.uuid4().hex[:12]}"
    send_event(base_event(
        event="PreToolUse",
        status="running_tool",
        tool="Write",
        tool_input={
            "file_path": "config.json",
            "content": '{\n  "port": 3000,\n  "host": "0.0.0.0",\n  "debug": false,\n  "database": {\n    "url": "postgres://localhost/app",\n    "pool_size": 10\n  }\n}',
        },
        tool_use_id=tool_use_id,
    ))
    time.sleep(0.3)

    response = send_event(base_event(
        event="PermissionRequest",
        status="waiting_for_approval",
        tool="Write",
        tool_input={
            "file_path": "config.json",
            "content": '{\n  "port": 3000,\n  "host": "0.0.0.0",\n  "debug": false,\n  "database": {\n    "url": "postgres://localhost/app",\n    "pool_size": 10\n  }\n}',
        },
    ), wait_response=True)

    if response:
        decision = response.get("decision", "none")
        print(f"  → User chose: {decision}")
    print()


def sim_question():
    """Simulate AskUserQuestion with multiple options."""
    print("\n❓ Simulating: Claude's Question (AskUserQuestion)")
    print("  → Shows question with numbered option buttons")

    tool_use_id = f"tu_{uuid.uuid4().hex[:12]}"
    question_input = {
        "questions": [
            {
                "question": "I found 3 authentication bugs. Which should I fix first?",
                "options": [
                    {"label": "Fix token refresh", "description": "Critical: tokens expire silently causing 401s"},
                    {"label": "Fix session handling", "description": "Medium: sessions persist after logout"},
                    {"label": "Fix CORS headers", "description": "Low: preflight requests fail on staging"},
                    {"label": "Fix all three", "description": "Will take longer but addresses everything"},
                ],
            }
        ],
    }

    send_event(base_event(
        event="PreToolUse",
        status="running_tool",
        tool="AskUserQuestion",
        tool_input=question_input,
        tool_use_id=tool_use_id,
    ))
    time.sleep(0.3)

    response = send_event(base_event(
        event="PermissionRequest",
        status="waiting_for_approval",
        tool="AskUserQuestion",
        tool_input=question_input,
    ), wait_response=True)

    if response:
        decision = response.get("decision", "none")
        print(f"  → User chose: {decision}")
    print()


def sim_end():
    """End the simulated session."""
    print("\n👋 Ending simulated session")
    send_event(base_event(
        event="SessionEnd",
        status="ended",
    ))


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    scenario = sys.argv[1].lower()

    print(f"🐦 Claude Perch UI Simulator")
    print(f"   Session: {SESSION_ID}")
    print(f"   Socket:  {SOCKET_PATH}")

    sim_session_start()

    if scenario == "processing":
        sim_processing()
    elif scenario == "done":
        sim_done()
    elif scenario == "approval" or scenario == "bash":
        sim_approval_bash()
    elif scenario == "edit":
        sim_approval_edit()
    elif scenario == "write":
        sim_approval_generic()
    elif scenario == "question":
        sim_question()
    elif scenario == "all":
        print("\n═══ Running all scenarios ═══")
        sim_processing()
        sim_approval_bash()
        sim_approval_edit()
        sim_approval_generic()
        sim_question()
        sim_done()
    else:
        print(f"Unknown scenario: {scenario}")
        print(__doc__)
        sys.exit(1)

    sim_end()
    print("✨ Simulation complete!")


if __name__ == "__main__":
    main()
