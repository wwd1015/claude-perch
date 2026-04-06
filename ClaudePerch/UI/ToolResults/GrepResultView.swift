//
//  GrepResultView.swift
//  ClaudePerch
//
//  View for rendering Grep tool results
//

import SwiftUI

struct GrepResultContent: View {
    let result: GrepResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch result.mode {
            case .filesWithMatches:
                // Show file list
                if result.filenames.isEmpty {
                    Text("No matches found")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                } else {
                    FileListView(files: result.filenames, limit: 10)
                }

            case .content:
                // Show matching content
                if let content = result.content, !content.isEmpty {
                    CodePreview(content: content, maxLines: 15)
                } else {
                    Text("No matches found")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                }

            case .count:
                Text("\(result.numFiles) files with matches")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }
}
