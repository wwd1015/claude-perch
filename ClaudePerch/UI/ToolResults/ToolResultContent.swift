//
//  ToolResultContent.swift
//  ClaudePerch
//
//  Main dispatcher that routes each tool result type to its individual view
//

import SwiftUI

// MARK: - Tool Result Content Dispatcher

struct ToolResultContent: View {
    let tool: ToolCallItem

    var body: some View {
        if let structured = tool.structuredResult {
            switch structured {
            case .read(let r):
                ReadResultContent(result: r)
            case .edit(let r):
                EditResultContent(result: r, toolInput: tool.input)
            case .write(let r):
                WriteResultContent(result: r)
            case .bash(let r):
                BashResultContent(result: r)
            case .grep(let r):
                GrepResultContent(result: r)
            case .glob(let r):
                GlobResultContent(result: r)
            case .todoWrite(let r):
                TodoWriteResultContent(result: r)
            case .task(let r):
                TaskResultContent(result: r)
            case .webFetch(let r):
                WebFetchResultContent(result: r)
            case .webSearch(let r):
                WebSearchResultContent(result: r)
            case .askUserQuestion(let r):
                AskUserQuestionResultContent(result: r)
            case .bashOutput(let r):
                BashOutputResultContent(result: r)
            case .killShell(let r):
                KillShellResultContent(result: r)
            case .exitPlanMode(let r):
                ExitPlanModeResultContent(result: r)
            case .mcp(let r):
                MCPResultContent(result: r)
            case .generic(let r):
                GenericResultContent(result: r)
            }
        } else if tool.name == "Edit" {
            // Special fallback for Edit - show diff from input params
            EditInputDiffView(input: tool.input)
        } else if let result = tool.result {
            // Fallback to raw text display
            GenericTextContent(text: result)
        } else {
            EmptyView()
        }
    }
}
