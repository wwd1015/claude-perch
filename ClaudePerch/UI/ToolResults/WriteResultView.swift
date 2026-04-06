//
//  WriteResultView.swift
//  ClaudePerch
//
//  View for rendering Write tool results
//

import SwiftUI

struct WriteResultContent: View {
    let result: WriteResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Action and filename
            HStack(spacing: 4) {
                Text(result.type == .create ? "Created" : "Wrote")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                Text(result.filename)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
            }

            // Content preview for new files
            if result.type == .create && !result.content.isEmpty {
                CodePreview(content: result.content, maxLines: 8)
            } else if let patches = result.structuredPatch, !patches.isEmpty {
                DiffView(patches: patches)
            }
        }
    }
}
