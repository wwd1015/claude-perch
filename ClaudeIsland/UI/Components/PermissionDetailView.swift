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
        }
        .padding(12)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

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

    // MARK: - AskUserQuestion (matches Vibe Island: teal option buttons)

    private var askUserQuestionView: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 6) {
                Text("Claude asks")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }

            // Question text
            if let question = extractQuestionText() {
                Text(question)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(3)
            }

            // Option buttons (teal-tinted like Vibe Island)
            let options = extractQuestionOptions()
            if !options.isEmpty {
                VStack(spacing: 5) {
                    ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                        Button {
                            onAnswer?(option)
                        } label: {
                            HStack(spacing: 8) {
                                Text("\u{2318}\(index + 1)")
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.5))
                                Text(option)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(red: 0.15, green: 0.35, blue: 0.35)) // Teal tint
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

    // MARK: - Approval Buttons (full-width, side by side like Vibe Island)

    private var approvalButtons: some View {
        HStack(spacing: 8) {
            Button {
                onDeny()
            } label: {
                HStack(spacing: 4) {
                    Text("Deny")
                        .font(.system(size: 13, weight: .medium))
                    Text("\u{2318}N")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                }
                .foregroundColor(.white.opacity(0.7))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            Button {
                onApprove()
            } label: {
                HStack(spacing: 4) {
                    Text("Allow")
                        .font(.system(size: 13, weight: .semibold))
                    Text("\u{2318}Y")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.black.opacity(0.5))
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
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
}
