//
//  TaskResultView.swift
//  ClaudePerch
//
//  Views for rendering Task, TodoWrite, AskUserQuestion, and ExitPlanMode tool results
//

import SwiftUI

// MARK: - Task Result View

struct TaskResultContent: View {
    let result: TaskResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Status and stats
            HStack(spacing: 8) {
                Text(result.status.capitalized)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(statusColor)

                if let duration = result.totalDurationMs {
                    Text("\(formatDuration(duration))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                }

                if let tools = result.totalToolUseCount {
                    Text("\(tools) tools")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                }
            }

            // Content summary
            if !result.content.isEmpty {
                Text(result.content.prefix(200) + (result.content.count > 200 ? "..." : ""))
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(5)
            }
        }
    }

    private var statusColor: Color {
        switch result.status {
        case "completed": return .green.opacity(0.7)
        case "in_progress": return .orange.opacity(0.7)
        case "failed", "error": return .red.opacity(0.7)
        default: return .white.opacity(0.5)
        }
    }

    private func formatDuration(_ ms: Int) -> String {
        if ms >= 60000 {
            return "\(ms / 60000)m \((ms % 60000) / 1000)s"
        } else if ms >= 1000 {
            return "\(ms / 1000)s"
        }
        return "\(ms)ms"
    }
}

// MARK: - TodoWrite Result View

struct TodoWriteResultContent: View {
    let result: TodoWriteResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(result.newTodos.enumerated()), id: \.offset) { _, todo in
                HStack(spacing: 6) {
                    // Status icon
                    Image(systemName: todoIcon(for: todo.status))
                        .font(.system(size: 10))
                        .foregroundColor(todoColor(for: todo.status))
                        .frame(width: 12)

                    Text(todo.content)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(todo.status == "completed" ? 0.4 : 0.7))
                        .strikethrough(todo.status == "completed")
                        .lineLimit(2)
                }
            }
        }
    }

    private func todoIcon(for status: String) -> String {
        switch status {
        case "completed": return "checkmark.circle.fill"
        case "in_progress": return "circle.lefthalf.filled"
        default: return "circle"
        }
    }

    private func todoColor(for status: String) -> Color {
        switch status {
        case "completed": return .green.opacity(0.7)
        case "in_progress": return .orange.opacity(0.7)
        default: return .white.opacity(0.4)
        }
    }
}

// MARK: - AskUserQuestion Result View

struct AskUserQuestionResultContent: View {
    let result: AskUserQuestionResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(result.questions.enumerated()), id: \.offset) { index, question in
                VStack(alignment: .leading, spacing: 4) {
                    // Question
                    Text(question.question)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.6))

                    // Answer
                    if let answer = result.answers["\(index)"] {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.system(size: 9))
                            Text(answer)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.green.opacity(0.7))
                    }
                }
            }
        }
    }
}

// MARK: - ExitPlanMode Result View

struct ExitPlanModeResultContent: View {
    let result: ExitPlanModeResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let path = result.filePath {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 10))
                    Text(URL(fileURLWithPath: path).lastPathComponent)
                        .font(.system(size: 11, design: .monospaced))
                }
                .foregroundColor(.white.opacity(0.6))
            }

            if let plan = result.plan, !plan.isEmpty {
                Text(plan.prefix(200) + (plan.count > 200 ? "..." : ""))
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(6)
            }
        }
    }
}
