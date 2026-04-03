//
//  PermissionDetailView.swift
//  ClaudeIsland
//
//  Rich permission approval UI: inline diff preview for Edit,
//  clickable option buttons for AskUserQuestion, command preview for Bash.
//

import SwiftUI

// MARK: - Permission Detail View

/// Shows rich context for a permission request based on tool type
struct PermissionDetailView: View {
    let context: PermissionContext
    let onApprove: () -> Void
    let onDeny: () -> Void
    /// For AskUserQuestion: sends the selected option text back
    let onAnswer: ((String) -> Void)?

    init(context: PermissionContext, onApprove: @escaping () -> Void, onDeny: @escaping () -> Void, onAnswer: ((String) -> Void)? = nil) {
        self.context = context
        self.onApprove = onApprove
        self.onDeny = onDeny
        self.onAnswer = onAnswer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Tool header
            HStack(spacing: 6) {
                Image(systemName: toolIcon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(TerminalColors.amber)
                Text(MCPToolFormatter.formatToolName(context.toolName))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(TerminalColors.amber)
                if let filePath = extractString("file_path") {
                    Text(shortenPath(filePath))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                }
                Spacer()
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

            // Action buttons (skip for AskUserQuestion which has its own buttons)
            if context.toolName != "AskUserQuestion" {
                approvalButtons
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Edit Diff View

    private var editDiffView: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let oldString = extractString("old_string"),
               let newString = extractString("new_string") {
                // Show inline diff
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 1) {
                        // Removed lines
                        ForEach(oldString.components(separatedBy: "\n"), id: \.self) { line in
                            HStack(spacing: 4) {
                                Text("-")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(Color(red: 0.9, green: 0.3, blue: 0.3))
                                Text(line)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(Color(red: 0.9, green: 0.3, blue: 0.3).opacity(0.8))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.red.opacity(0.08))
                        }
                        // Added lines
                        ForEach(newString.components(separatedBy: "\n"), id: \.self) { line in
                            HStack(spacing: 4) {
                                Text("+")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(Color(red: 0.3, green: 0.85, blue: 0.4))
                                Text(line)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(Color(red: 0.3, green: 0.85, blue: 0.4).opacity(0.8))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.08))
                        }
                    }
                }
                .frame(maxHeight: 120)

                // Change summary
                let removedCount = oldString.components(separatedBy: "\n").count
                let addedCount = newString.components(separatedBy: "\n").count
                Text("+\(addedCount) -\(removedCount)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
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
                let lineCount = content.components(separatedBy: "\n").count
                Text("New file (\(lineCount) lines)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))

                // Show first few lines
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(content.components(separatedBy: "\n").prefix(8).enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white.opacity(0.6))
                                .lineLimit(1)
                        }
                        if content.components(separatedBy: "\n").count > 8 {
                            Text("...")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white.opacity(0.3))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                    .background(Color.white.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .frame(maxHeight: 100)
            } else {
                genericPreview
            }
        }
    }

    // MARK: - Bash Preview

    private var bashPreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let command = extractString("command") {
                HStack(spacing: 4) {
                    Text("$")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(TerminalColors.green)
                    Text(command)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(3)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                genericPreview
            }
        }
    }

    // MARK: - AskUserQuestion View

    private var askUserQuestionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Show the question
            if let question = extractQuestionText() {
                Text(question)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(3)
            }

            // Show clickable option buttons
            let options = extractQuestionOptions()
            if !options.isEmpty {
                VStack(spacing: 4) {
                    ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                        Button {
                            onAnswer?(option)
                        } label: {
                            HStack(spacing: 6) {
                                Text("\u{2318}\(index + 1)")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.4))
                                    .frame(width: 28)
                                Text(option)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white.opacity(0.9))
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
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
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(4)
            }
        }
    }

    // MARK: - Approval Buttons

    private var approvalButtons: some View {
        HStack(spacing: 8) {
            Spacer()

            Button {
                onDeny()
            } label: {
                HStack(spacing: 4) {
                    Text("Deny")
                        .font(.system(size: 11, weight: .medium))
                    Text("\u{2318}N")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                }
                .foregroundColor(.white.opacity(0.6))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.1))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button {
                onApprove()
            } label: {
                HStack(spacing: 4) {
                    Text("Allow")
                        .font(.system(size: 11, weight: .medium))
                    Text("\u{2318}Y")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.black.opacity(0.4))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.9))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private var toolIcon: String {
        switch context.toolName {
        case "Edit": return "pencil"
        case "Write": return "doc.badge.plus"
        case "Bash": return "terminal"
        case "Read": return "doc.text"
        case "Glob", "Grep": return "magnifyingglass"
        case "AskUserQuestion": return "questionmark.bubble"
        default: return "wrench"
        }
    }

    private func extractString(_ key: String) -> String? {
        guard let input = context.toolInput,
              let codable = input[key],
              let str = codable.value as? String else { return nil }
        return str
    }

    private func shortenPath(_ path: String) -> String {
        let components = path.components(separatedBy: "/")
        if components.count <= 3 { return path }
        return ".../" + components.suffix(2).joined(separator: "/")
    }

    private func extractQuestionText() -> String? {
        guard let input = context.toolInput else { return nil }
        // AskUserQuestion has a "questions" array with "question" field
        if let questions = input["questions"]?.value as? [[String: Any]],
           let first = questions.first,
           let question = first["question"] as? String {
            return question
        }
        // Fallback: check for "question" directly
        if let question = input["question"]?.value as? String {
            return question
        }
        return nil
    }

    private func extractQuestionOptions() -> [String] {
        guard let input = context.toolInput else { return [] }
        // AskUserQuestion has questions[0].options[].label
        if let questions = input["questions"]?.value as? [[String: Any]],
           let first = questions.first,
           let options = first["options"] as? [[String: Any]] {
            return options.compactMap { $0["label"] as? String }
        }
        return []
    }
}
