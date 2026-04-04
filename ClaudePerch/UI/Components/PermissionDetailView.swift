//
//  PermissionDetailView.swift
//  ClaudePerch
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
    let onApproveAlways: (() -> Void)?

    init(context: PermissionContext, onApprove: @escaping () -> Void, onDeny: @escaping () -> Void, onAnswer: ((String) -> Void)? = nil, onApproveAlways: (() -> Void)? = nil) {
        self.context = context
        self.onApprove = onApprove
        self.onDeny = onDeny
        self.onAnswer = onAnswer
        self.onApproveAlways = onApproveAlways
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // For AskUserQuestion: skip the generic headers, go straight to Claude's Question
            // For other tools: show Permission Request + tool line
            if context.toolName != "AskUserQuestion" {
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

    // MARK: - AskUserQuestion (shows ALL questions at once with Submit All)

    private var askUserQuestionView: some View {
        AskUserQuestionMultiView(
            context: context,
            onAnswer: onAnswer
        )
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

    // MARK: - Approval Buttons (Deny / Allow / Always Allow / Bypass - matches terminal)

    private var approvalButtons: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                // Deny
                Button { onDeny() } label: {
                    Text("Deny")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                // Allow (one-time)
                Button { onApprove() } label: {
                    Text("Allow")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                // Always Allow
                Button { onAlwaysAllowAction() } label: {
                    Text("Always Allow")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(red: 0.3, green: 0.5, blue: 0.8))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                // Bypass (Esc in terminal - dismiss without answering)
                Button { onDeny() } label: {
                    Text("Bypass")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(red: 0.5, green: 0.25, blue: 0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func onAlwaysAllowAction() {
        if let handler = onApproveAlways {
            handler()
        } else {
            onApprove() // Fallback to regular approve
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

// MARK: - Multi-Question AskUserQuestion View

/// Shows ALL questions at once with selectable option chips and a "Submit All Answers" button
struct AskUserQuestionMultiView: View {
    let context: PermissionContext
    let onAnswer: ((String) -> Void)?

    @State private var selectedAnswers: [Int: String] = [:]

    private var allQuestions: [(question: String, options: [(label: String, description: String?)])] {
        guard let input = context.toolInput,
              let questions = input["questions"]?.value as? [[String: Any]] else { return [] }
        return questions.compactMap { q in
            guard let question = q["question"] as? String else { return nil }
            let options: [(label: String, description: String?)]
            if let opts = q["options"] as? [[String: Any]] {
                options = opts.compactMap { opt in
                    guard let label = opt["label"] as? String else { return nil }
                    return (label: label, description: opt["description"] as? String)
                }
            } else {
                options = []
            }
            return (question: question, options: options)
        }
    }

    private var allAnswered: Bool {
        let questions = allQuestions
        guard !questions.isEmpty else { return false }
        return questions.indices.allSatisfy { selectedAnswers[$0] != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 6) {
                Text("🧡")
                    .font(.system(size: 12))
                Text("Claude's Question")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(TerminalColors.amber)
                if allQuestions.count > 1 {
                    Text("(\(allQuestions.count) questions)")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }
            }

            // All questions
            let questions = allQuestions
            ForEach(Array(questions.enumerated()), id: \.offset) { qIndex, q in
                VStack(alignment: .leading, spacing: 6) {
                    // Question number + text
                    HStack(alignment: .top, spacing: 6) {
                        if questions.count > 1 {
                            Text("\(qIndex + 1).")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        Text(q.question)
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // Option chips (selectable)
                    FlowLayout(spacing: 5) {
                        ForEach(Array(q.options.enumerated()), id: \.offset) { oIndex, option in
                            Button {
                                selectedAnswers[qIndex] = option.label
                            } label: {
                                Text(option.label)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(selectedAnswers[qIndex] == option.label ? .white : .white.opacity(0.7))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        selectedAnswers[qIndex] == option.label
                                            ? Color(red: 0.2, green: 0.5, blue: 0.4)
                                            : Color.white.opacity(0.1)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // Warning if not all answered
            if !allAnswered && !questions.isEmpty {
                HStack(spacing: 4) {
                    Text("⚠")
                        .font(.system(size: 10))
                    Text("Please answer all questions")
                        .font(.system(size: 11))
                        .foregroundColor(TerminalColors.amber.opacity(0.7))
                }
            }

            // Submit All Answers button
            Button {
                // Serialize answers as JSON array
                let answers = (0..<allQuestions.count).map { selectedAnswers[$0] ?? "" }
                if let data = try? JSONSerialization.data(withJSONObject: answers),
                   let json = String(data: data, encoding: .utf8) {
                    onAnswer?(json)
                }
            } label: {
                Text("Submit All Answers")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(allAnswered ? .white : .white.opacity(0.4))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(allAnswered ? Color(red: 0.2, green: 0.6, blue: 0.3) : Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(!allAnswered)
        }
    }
}

// MARK: - Flow Layout (wrapping horizontal layout for option chips)

struct FlowLayout: Layout {
    var spacing: CGFloat = 5

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}
