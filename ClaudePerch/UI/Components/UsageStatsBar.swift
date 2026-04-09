//
//  UsageStatsBar.swift
//  ClaudePerch
//
//  Usage stats bar showing rate limit usage as a compact progress bar with
//  color coding and reset time. Merges data from the OAuth API (UsageStatsProvider)
//  and real-time hook events (SessionState.rateLimits).
//

import Combine
import SwiftUI

struct UsageStatsBar: View {
    @ObservedObject var usageProvider: UsageStatsProvider
    @ObservedObject var sessionMonitor: ClaudeSessionMonitor

    /// Resolved usage: prefer real-time hook data, fall back to API data
    private var resolvedUsage: ResolvedUsage? {
        // Try hook-provided rate limits first (most recent session with data)
        if let hookLimits = sessionMonitor.instances
            .sorted(by: { $0.lastActivity > $1.lastActivity })
            .compactMap({ $0.rateLimits })
            .first {
            let fiveHourUsed = hookLimits.fiveHour?.usedPercentage ?? 0
            let fiveHourReset: Date? = hookLimits.fiveHour?.resetsAt.map { Date(timeIntervalSince1970: $0) }
            let sevenDayUsed = hookLimits.sevenDay?.usedPercentage ?? 0
            let sevenDayReset: Date? = hookLimits.sevenDay?.resetsAt.map { Date(timeIntervalSince1970: $0) }
            return ResolvedUsage(
                fiveHourUsedPercent: fiveHourUsed,
                fiveHourResetsAt: fiveHourReset,
                sevenDayUsedPercent: sevenDayUsed,
                sevenDayResetsAt: sevenDayReset
            )
        }
        // Fall back to API data
        if let api = usageProvider.stats {
            return ResolvedUsage(
                fiveHourUsedPercent: api.fiveHourPercent,
                fiveHourResetsAt: api.fiveHourResetsAt,
                sevenDayUsedPercent: api.sevenDayPercent,
                sevenDayResetsAt: api.sevenDayResetsAt
            )
        }
        return nil
    }

    var body: some View {
        if let usage = resolvedUsage {
            let remaining = max(0, 100 - usage.fiveHourUsedPercent)

            HStack(spacing: 6) {
                // Compact progress bar
                usageBar(remaining: remaining)

                // Percentage label
                Text("\(Int(remaining))%")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(colorForRemaining(remaining))

                // Reset time
                if let reset = usage.fiveHourResetsAt, reset.timeIntervalSinceNow > 0 {
                    Text("resets \(formatResetTime(reset))")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.3))
                }

                Spacer()

                // Session count
                let count = sessionMonitor.instances.count
                Text("\(count) session\(count == 1 ? "" : "s")")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(.vertical, 2)
            .onAppear {
                usageProvider.refresh()
            }
            .onReceive(Timer.publish(every: 300, on: .main, in: .common).autoconnect()) { _ in
                usageProvider.refresh()
            }
        } else {
            // No usage data yet: show minimal session info
            HStack(spacing: 4) {
                let count = sessionMonitor.instances.count
                if let oldest = sessionMonitor.instances.min(by: { $0.createdAt < $1.createdAt }) {
                    let elapsed = Date().timeIntervalSince(oldest.createdAt)
                    let hours = Int(elapsed / 3600)
                    let minutes = Int(elapsed.truncatingRemainder(dividingBy: 3600) / 60)
                    Text("\(hours)h \(String(format: "%02d", minutes))m")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))

                    Text("|")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.15))
                }

                Text("\(count) session\(count == 1 ? "" : "s")")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.3))

                Spacer()
            }
            .padding(.vertical, 2)
            .onAppear {
                usageProvider.refresh()
            }
        }
    }

    // MARK: - Progress Bar

    @ViewBuilder
    private func usageBar(remaining: Double) -> some View {
        let fraction = remaining / 100.0
        let barColor = colorForRemaining(remaining)

        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: 2)
                    .fill(.white.opacity(0.08))

                // Fill
                RoundedRectangle(cornerRadius: 2)
                    .fill(barColor)
                    .frame(width: max(0, geo.size.width * fraction))
            }
        }
        .frame(width: 48, height: 4)
    }

    // MARK: - Color Coding

    /// Green >50% remaining, yellow 20-50%, red <20%
    private func colorForRemaining(_ remaining: Double) -> Color {
        if remaining > 50 {
            return Color(red: 0.3, green: 0.8, blue: 0.45)  // green
        } else if remaining > 20 {
            return Color(red: 0.9, green: 0.7, blue: 0.2)   // yellow/amber
        } else {
            return Color(red: 0.9, green: 0.3, blue: 0.25)  // red
        }
    }

    // MARK: - Formatting

    /// Format remaining time until reset as "in Xh XXm"
    private func formatResetTime(_ date: Date) -> String {
        let remaining = date.timeIntervalSinceNow
        if remaining <= 0 { return "now" }
        let totalMinutes = Int(remaining / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "in \(hours)h \(String(format: "%02d", minutes))m"
        }
        return "in \(minutes)m"
    }
}

// MARK: - Resolved Usage

/// Unified usage data from either hook events or the OAuth API
private struct ResolvedUsage {
    let fiveHourUsedPercent: Double
    let fiveHourResetsAt: Date?
    let sevenDayUsedPercent: Double
    let sevenDayResetsAt: Date?
}
