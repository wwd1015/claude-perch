//
//  EditResultView.swift
//  ClaudePerch
//
//  Views for rendering Edit tool results and input diffs
//

import SwiftUI

// MARK: - Edit Result View

struct EditResultContent: View {
    let result: EditResult
    var toolInput: [String: String] = [:]

    /// Get old string - prefer result, fallback to input
    private var oldString: String {
        if !result.oldString.isEmpty {
            return result.oldString
        }
        return toolInput["old_string"] ?? ""
    }

    /// Get new string - prefer result, fallback to input
    private var newString: String {
        if !result.newString.isEmpty {
            return result.newString
        }
        return toolInput["new_string"] ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Always use SimpleDiffView for consistent styling (no @@ headers)
            if !oldString.isEmpty || !newString.isEmpty {
                SimpleDiffView(oldString: oldString, newString: newString, filename: result.filename)
            }

            if result.userModified {
                Text("(User modified)")
                    .font(.system(size: 10))
                    .foregroundColor(.orange.opacity(0.7))
            }
        }
    }
}

// MARK: - Edit Input Diff View (fallback when no structured result)

struct EditInputDiffView: View {
    let input: [String: String]

    private var filename: String {
        if let path = input["file_path"] {
            return URL(fileURLWithPath: path).lastPathComponent
        }
        return "file"
    }

    private var oldString: String {
        input["old_string"] ?? ""
    }

    private var newString: String {
        input["new_string"] ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Show diff from input with integrated filename
            if !oldString.isEmpty || !newString.isEmpty {
                SimpleDiffView(oldString: oldString, newString: newString, filename: filename)
            }
        }
    }
}
