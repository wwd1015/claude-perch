//
//  WebResultView.swift
//  ClaudePerch
//
//  Views for rendering WebFetch and WebSearch tool results
//

import SwiftUI

// MARK: - WebFetch Result View

struct WebFetchResultContent: View {
    let result: WebFetchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // URL and status
            HStack(spacing: 6) {
                Text("\(result.code)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(result.code < 400 ? .green.opacity(0.7) : .red.opacity(0.7))

                Text(truncateUrl(result.url))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
            }

            // Result summary
            if !result.result.isEmpty {
                Text(result.result.prefix(300) + (result.result.count > 300 ? "..." : ""))
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(8)
            }
        }
    }

    private func truncateUrl(_ url: String) -> String {
        if url.count > 50 {
            return String(url.prefix(47)) + "..."
        }
        return url
    }
}

// MARK: - WebSearch Result View

struct WebSearchResultContent: View {
    let result: WebSearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if result.results.isEmpty {
                Text("No results found")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
            } else {
                ForEach(Array(result.results.prefix(5).enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.blue.opacity(0.8))
                            .lineLimit(1)

                        if !item.snippet.isEmpty {
                            Text(item.snippet)
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.5))
                                .lineLimit(2)
                        }
                    }
                }

                if result.results.count > 5 {
                    Text("... and \(result.results.count - 5) more results")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.3))
                }
            }
        }
    }
}
