//
//  BashResultView.swift
//  ClaudePerch
//
//  Views for rendering Bash and BashOutput tool results
//

import SwiftUI

// MARK: - Bash Result View

struct BashResultContent: View {
    let result: BashResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Background task indicator
            if let bgId = result.backgroundTaskId {
                HStack(spacing: 4) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 10))
                    Text("Background task: \(bgId)")
                        .font(.system(size: 10, design: .monospaced))
                }
                .foregroundColor(.blue.opacity(0.7))
            }

            // Return code interpretation
            if let interpretation = result.returnCodeInterpretation {
                Text(interpretation)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            }

            // Stdout
            if !result.stdout.isEmpty {
                CodePreview(content: result.stdout, maxLines: 15)
            }

            // Stderr (shown in red)
            if !result.stderr.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("stderr:")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.red.opacity(0.7))
                    Text(result.stderr)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.red.opacity(0.8))
                        .lineLimit(10)
                }
            }

            // Empty state
            if !result.hasOutput && result.backgroundTaskId == nil && result.returnCodeInterpretation == nil {
                Text("(No content)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
            }
        }
    }
}

// MARK: - BashOutput Result View

struct BashOutputResultContent: View {
    let result: BashOutputResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Status
            HStack(spacing: 6) {
                Text("Status: \(result.status)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))

                if let exitCode = result.exitCode {
                    Text("Exit: \(exitCode)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(exitCode == 0 ? .green.opacity(0.6) : .red.opacity(0.6))
                }
            }

            // Output
            if !result.stdout.isEmpty {
                CodePreview(content: result.stdout, maxLines: 10)
            }

            if !result.stderr.isEmpty {
                Text(result.stderr)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.red.opacity(0.7))
                    .lineLimit(5)
            }
        }
    }
}

// MARK: - KillShell Result View

struct KillShellResultContent: View {
    let result: KillShellResult

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "xmark.circle")
                .font(.system(size: 11))
                .foregroundColor(.red.opacity(0.6))

            Text(result.message.isEmpty ? "Shell \(result.shellId) terminated" : result.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
        }
    }
}
