//
//  UsageStatsBar.swift
//  ClaudePerch
//
//  Usage stats bar showing session count, rate limit usage, and reset time.
//  Extracted from NotchView for reusability.
//

import Combine
import SwiftUI

struct UsageStatsBar: View {
    @ObservedObject var usageProvider: UsageStatsProvider
    @ObservedObject var sessionMonitor: ClaudeSessionMonitor

    var body: some View {
        let totalSessions = sessionMonitor.instances.count
        let activeSessions = sessionMonitor.instances.filter { $0.phase == .processing || $0.phase == .compacting }.count

        HStack(spacing: 4) {
            // Status indicator
            Circle()
                .fill(activeSessions > 0 ? Color.orange : TerminalColors.green)
                .frame(width: 8, height: 8)

            // Format: "5h X% | resets in Xh XXm"
            if let usage = usageProvider.stats {
                Text("5h")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.7))
                Text("\(Int(usage.fiveHourPercent))%")
                    .font(.system(size: 10))
                    .foregroundColor(usage.fiveHourPercent > 80 ? Color.red.opacity(0.9) : .white.opacity(0.4))

                Text("|")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.2))

                // Show reset time based on 5h window
                if let reset = usage.fiveHourResetsAt {
                    Text("resets in")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.3))
                    Text(formatResetTime(reset))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                }
            } else {
                // Fallback: show session time when no usage data
                if let oldest = sessionMonitor.instances.min(by: { $0.createdAt < $1.createdAt }) {
                    let elapsed = Date().timeIntervalSince(oldest.createdAt)
                    let hours = Int(elapsed / 3600)
                    let minutes = Int(elapsed.truncatingRemainder(dividingBy: 3600) / 60)
                    Text("\(hours)h")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.7))
                    Text("\(String(format: "%02d", minutes))m")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                }
            }

            Text("|")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.2))

            // Total sessions info
            Text("\(totalSessions) session\(totalSessions == 1 ? "" : "s")")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.4))

            Spacer()
        }
        .onAppear {
            usageProvider.refresh()
        }
        .onReceive(Timer.publish(every: 300, on: .main, in: .common).autoconnect()) { _ in
            usageProvider.refresh()
        }
    }

    /// Format remaining time until reset as "Xh XXm"
    private func formatResetTime(_ date: Date) -> String {
        let remaining = date.timeIntervalSinceNow
        if remaining <= 0 { return "now" }
        let totalMinutes = Int(remaining / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours)h \(String(format: "%02d", minutes))m"
        }
        return "\(minutes)m"
    }
}
