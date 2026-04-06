import Combine
import Foundation

@MainActor
class CompletionQueue: ObservableObject {
    @Published var currentCompletion: CompletionEntry?
    @Published var isShowing: Bool = false

    private var queue: [CompletionEntry] = []
    private var autoCollapseTimer: DispatchWorkItem?
    private var completionHasBeenEntered: Bool = false

    static let autoCollapseDuration: TimeInterval = 5.0

    struct CompletionEntry: Identifiable {
        let id: String
        let sessionId: String
        let timestamp: Date
    }

    func enqueue(sessionId: String) {
        // Don't duplicate
        guard currentCompletion?.sessionId != sessionId,
              !queue.contains(where: { $0.sessionId == sessionId }) else { return }

        let entry = CompletionEntry(id: sessionId, sessionId: sessionId, timestamp: Date())

        if isShowing {
            queue.append(entry)
        } else {
            show(entry)
        }
    }

    func setHovering(_ hovering: Bool) {
        if hovering {
            completionHasBeenEntered = true
            autoCollapseTimer?.cancel()
            autoCollapseTimer = nil
        } else if completionHasBeenEntered {
            startAutoCollapseTimer()
        }
    }

    func dismiss() {
        autoCollapseTimer?.cancel()
        autoCollapseTimer = nil

        if let next = queue.first {
            queue.removeFirst()
            show(next)
        } else {
            currentCompletion = nil
            isShowing = false
        }
    }

    func cancelAll() {
        autoCollapseTimer?.cancel()
        autoCollapseTimer = nil
        queue.removeAll()
        currentCompletion = nil
        isShowing = false
        completionHasBeenEntered = false
    }

    private func show(_ entry: CompletionEntry) {
        currentCompletion = entry
        isShowing = true
        completionHasBeenEntered = false
        startAutoCollapseTimer()
    }

    private func startAutoCollapseTimer() {
        autoCollapseTimer?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.dismiss()
        }
        autoCollapseTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.autoCollapseDuration, execute: item)
    }
}
