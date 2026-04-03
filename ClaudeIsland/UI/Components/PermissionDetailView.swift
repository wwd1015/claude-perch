//
//  PermissionDetailView.swift
//  ClaudeIsland
//
//  Rich permission approval UI matching Vibe Island's design:
//  - Amber dot + "Permission Request" header
//  - Inline diff with line numbers for Edit
//  - Command preview for Bash
//  - Clickable option buttons for AskUserQuestion
//  - Full-width Deny/Allow buttons with keyboard shortcuts
//

import SwiftUI

struct PermissionDetailView: View {
    let context: PermissionContext
    let onApprove: () -> Void
    let onDeny: () -> Void
    let onAnswer: ((String) -> Void)?

    init(context: PermissionContext, onApprove: @escaping () -> Void, onDeny: @escaping () -> Void, onAnswer: ((String) -> Void)? = nil) {
        self.context = context
        self.onApprove = onApprove
        self.onDeny = onDeny
        self.onAnswer = onAnswer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: amber dot + "Permission Request"
            HStack(spacing: 8) {
                Circle()
                    .fill(TerminalColors.amber)
                    .frame(width: 8, height: 8)
                Text("Permission Request")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
            }

            // Tool line: ⚠ Edit src/auth/middleware.ts
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(TerminalColors.amber)
                Text(MCPToolFormatter.formatToolName(context.toolName))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(TerminalColors.amber)
                if let filePath = extractString("file_path") {
                    Text(filePath)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(1)
                }
            }

            // Tool-specific content
            switch context.toolName {
            case "Edit":
                editDiffView
            case "Write":
                writePreview
            case "Bash":
                bashPreview
            case "AskUserQuestion":
                askUserQuestionView
            default:
                genericPreview
            }

            // Deny / Allow buttons (skip for AskUserQuestion)
            if context.toolName != "AskUserQuestion" {
                approvalButtons
            }

            // "Show all N sessions" link (like Vibe Island)
            if sessionCount > 1 {
                Button {} label: {
                    Text("Show all \(sessionCount) sessions")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// Number of active sessions (passed from parent)
    private var sessionCount: Int { 1 } // TODO: pass from parent

    // MARK: - Edit Diff (matches Vibe Island: line numbers + red/green)

    private var editDiffView: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let oldString = extractString("old_string"),
               let newString = extractString("new_string") {

                let oldLines = oldString.components(separatedBy: "\n")
                let newLines = newString.components(separatedBy: "\n")

                // Diff code block with dark background
                VStack(alignment: .leading, spacing: 0) {
                    // Removed lines (red)
                    ForEach(Array(oldLines.enumerated()), id: \.offset) { index, line in
                        HStack(spacing: 0) {
                            // Line number
                            Text("\(index + 1)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white.opacity(0.25))
                                .frame(width: 24, alignment: .trailing)
                            Text(" - ")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 1)
                        .background(Color.red.opacity(0.1))
                    }

                    // Added lines (green)
                    ForEach(Array(newLines.enumerated()), id: \.offset) { index, line in
                        HStack(spacing: 0) {
                            Text("\(oldLines.count + index + 1)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white.opacity(0.25))
                                .frame(width: 24, alignment: .trailing)
                            Text(" + ")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(red: 0.4, green: 0.9, blue: 0.4))
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(Color(red: 0.4, green: 0.9, blue: 0.4))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 1)
                        .background(Color.green.opacity(0.08))
                    }
                }
                .padding(8)
                .background(Color.black.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Change summary
                Text("+\(newLines.count) -\(oldLines.count)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
            } else {
                genericPreview
            }
        }
    }

    // MARK: - Write Preview

    private var writePreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let content = extractString("content") {
                let lines = content.components(separatedBy: "\n")
                Text("New file (\(lines.count) lines)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.prefix(8).enumerated()), id: \.offset) { index, line in
                        HStack(spacing: 0) {
                            Text("\(index + 1)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white.opacity(0.25))
                                .frame(width: 24, alignment: .trailing)
                            Text("   ")
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.white.opacity(0.6))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 1)
                    }
                    if lines.count > 8 {
                        Text("       ...")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white.opacity(0.3))
                    }
                }
                .padding(8)
                .background(Color.black.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                genericPreview
            }
        }
    }

    // MARK: - Bash Preview

    private var bashPreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let command = extractString("command") {
                HStack(spacing: 6) {
                    Text("$")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(TerminalColors.green)
                    Text(command)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(4)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                genericPreview
            }
        }
    }

    // MARK: - AskUserQuestion (Vibe Island: "Claude's Question" + option cards)

    private var askUserQuestionView: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: orange heart + "Claude's Question"
            HStack(spacing: 6) {
                Text("🧡")
                    .font(.system(size: 12))
                Text("Claude's Question")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(TerminalColors.amber)
            }

            // Question text
            if let question = extractQuestionText() {
                Text(question)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Option buttons with label + description (like Vibe Island)
            let options = extractQuestionOptionsWithDescriptions()
            if !options.isEmpty {
                VStack(spacing: 5) {
                    ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                        Button {
                            onAnswer?(option.label)
                        } label: {
                            HStack(spacing: 10) {
                                // Number badge
                                Text("\(index + 1)")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 24, height: 24)
                                    .background(Color.white.opacity(0.15))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))

                                // Label + description
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.label)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.white)
                                    if let desc = option.description {
                                        Text(desc)
                                            .font(.system(size: 11))
                                            .foregroundColor(.white.opacity(0.5))
                                    }
                                }

                                Spacer()

                                // Shortcut
                                Text("^\(index + 1)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.3))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(red: 0.12, green: 0.25, blue: 0.28))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Generic Preview

    private var genericPreview: some View {
        Group {
            if let formatted = context.formattedInput {
                Text(formatted)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(4)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: - Approval Buttons (4 buttons like Vibe Island)

    private var approvalButtons: some View {
        HStack(spacing: 6) {
            // Deny (dark)
            approvalButton(label: "Deny", color: Color.white.opacity(0.1), textColor: .white.opacity(0.7)) {
                onDeny()
            }

            // Allow Once (dark)
            approvalButton(label: "Allow Once", color: Color.white.opacity(0.1), textColor: .white.opacity(0.7)) {
                onApprove()
            }

            // Always Allow (blue)
            approvalButton(label: "Always Allow", color: Color(red: 0.3, green: 0.5, blue: 0.8), textColor: .white) {
                onApprove()
            }

            // Bypass (red/orange)
            approvalButton(label: "Bypass", color: Color(red: 0.7, green: 0.35, blue: 0.3), textColor: .white) {
                onApprove()
            }
        }
    }

    private func approvalButton(label: String, color: Color, textColor: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(textColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func extractString(_ key: String) -> String? {
        guard let input = context.toolInput,
              let codable = input[key],
              let str = codable.value as? String else { return nil }
        return str
    }

    private func extractQuestionText() -> String? {
        guard let input = context.toolInput else { return nil }
        if let questions = input["questions"]?.value as? [[String: Any]],
           let first = questions.first,
           let question = first["question"] as? String {
            return question
        }
        if let question = input["question"]?.value as? String {
            return question
        }
        return nil
    }

    private func extractQuestionOptions() -> [String] {
        guard let input = context.toolInput else { return [] }
        if let questions = input["questions"]?.value as? [[String: Any]],
           let first = questions.first,
           let options = first["options"] as? [[String: Any]] {
            return options.compactMap { $0["label"] as? String }
        }
        return []
    }

    /// Extract options with both label and description
    private func extractQuestionOptionsWithDescriptions() -> [(label: String, description: String?)] {
        guard let input = context.toolInput else { return [] }
        if let questions = input["questions"]?.value as? [[String: Any]],
           let first = questions.first,
           let options = first["options"] as? [[String: Any]] {
            return options.compactMap { opt -> (label: String, description: String?)? in
                guard let label = opt["label"] as? String else { return nil }
                let desc = opt["description"] as? String
                return (label: label, description: desc)
            }
        }
        return []
    }
}
