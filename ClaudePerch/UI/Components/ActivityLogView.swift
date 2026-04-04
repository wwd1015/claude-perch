//
//  ActivityLogView.swift
//  ClaudePerch
//
//  Per-session activity log showing recent tool calls with results.
//  Scrollable list of tool calls with file paths and outcomes.
//

import SwiftUI

struct ActivityLogView: View {
    let session: SessionState

    /// Extract recent tool calls from chat history items
    private var recentTools: [(id: String, tool: ToolCallItem)] {
        var tools: [(id: String, tool: ToolCallItem)] = []
        for item in session.chatItems {
            if case .toolCall(let toolItem) = item.type {
                tools.append((id: item.id, tool: toolItem))
            }
        }
        return Array(tools.suffix(10)) // Last 10 tools
    }

    var body: some View {
        if recentTools.isEmpty {
            EmptyView()
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(recentTools, id: \.id) { entry in
                        toolRow(entry.tool)
                    }
                }
            }
            .frame(maxHeight: 150)
            .padding(6)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private func toolRow(_ tool: ToolCallItem) -> some View {
        HStack(spacing: 6) {
            // Tool icon
            Image(systemName: iconForTool(tool.name))
                .font(.system(size: 9))
                .foregroundColor(tool.status == .running ? TerminalColors.green : .white.opacity(0.4))
                .frame(width: 12)

            // Tool name
            Text(MCPToolFormatter.formatToolName(tool.name))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(tool.status == .running ? TerminalColors.green : .white.opacity(0.5))

            // Input preview (file path, command, etc.)
            Text(tool.inputPreview)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))
                .lineLimit(1)

            Spacer(minLength: 0)

            // Status indicator
            switch tool.status {
            case .running:
                Text("...")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(TerminalColors.green)
            case .success:
                Image(systemName: "checkmark")
                    .font(.system(size: 8))
                    .foregroundColor(TerminalColors.green.opacity(0.6))
            case .error:
                Image(systemName: "xmark")
                    .font(.system(size: 8))
                    .foregroundColor(Color.red.opacity(0.6))
            case .interrupted:
                Image(systemName: "stop.fill")
                    .font(.system(size: 8))
                    .foregroundColor(TerminalColors.amber.opacity(0.6))
            default:
                EmptyView()
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
    }

    private func iconForTool(_ name: String) -> String {
        switch name {
        case "Read": return "doc.text"
        case "Edit": return "pencil"
        case "Write": return "doc.badge.plus"
        case "Bash": return "terminal"
        case "Glob", "Grep": return "magnifyingglass"
        case "Agent": return "person.2"
        case "Task": return "list.bullet"
        default: return "wrench"
        }
    }
}
