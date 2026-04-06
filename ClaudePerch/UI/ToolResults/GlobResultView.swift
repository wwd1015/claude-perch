//
//  GlobResultView.swift
//  ClaudePerch
//
//  View for rendering Glob tool results
//

import SwiftUI

struct GlobResultContent: View {
    let result: GlobResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if result.filenames.isEmpty {
                Text("No files found")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
            } else {
                FileListView(files: result.filenames, limit: 10)

                if result.truncated {
                    Text("... and more (truncated)")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.3))
                }
            }
        }
    }
}
