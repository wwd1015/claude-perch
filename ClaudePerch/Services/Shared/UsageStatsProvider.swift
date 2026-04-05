//
//  UsageStatsProvider.swift
//  ClaudePerch
//
//  Fetches API usage stats from Anthropic OAuth API.
//  Reads OAuth token from macOS Keychain, calls /api/oauth/usage,
//  and caches the result for 5 minutes.
//

import Combine
import Foundation
import Security

struct UsageStats: Equatable {
    let fiveHourPercent: Double
    let sevenDayPercent: Double
    let fiveHourResetsAt: Date?
    let sevenDayResetsAt: Date?
}

@MainActor
class UsageStatsProvider: ObservableObject {
    static let shared = UsageStatsProvider()

    @Published var stats: UsageStats?
    @Published var lastError: String?

    private var cachedAt: Date?
    private let cacheTTL: TimeInterval = 300 // 5 minutes
    private var fetchTask: Task<Void, Never>?

    private init() {}

    /// Fetch usage stats (uses cache if fresh)
    func refresh() {
        // Use cached value if fresh
        if let cachedAt, Date().timeIntervalSince(cachedAt) < cacheTTL, stats != nil {
            return
        }

        // Don't stack fetches
        guard fetchTask == nil else { return }

        fetchTask = Task {
            defer { fetchTask = nil }
            await fetchUsage()
        }
    }

    private func fetchUsage() async {
        // 1. Get OAuth token from Keychain
        guard let token = getOAuthToken() else {
            lastError = "No OAuth token"
            return
        }

        // 2. Call Anthropic usage API
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-perch/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else { return }

            if httpResponse.statusCode == 429 {
                lastError = "Rate limited"
                // Still cache to avoid hammering
                cachedAt = Date()
                return
            }

            guard httpResponse.statusCode == 200 else {
                lastError = "HTTP \(httpResponse.statusCode)"
                cachedAt = Date(timeIntervalSinceNow: -cacheTTL + 15) // retry in 15s
                return
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                lastError = "Invalid JSON"
                return
            }

            // Parse response — field is "utilization" (not "used_percentage")
            // and "resets_at" is an ISO 8601 string (not Unix timestamp)
            let fiveHour = json["five_hour"] as? [String: Any]
            let sevenDay = json["seven_day"] as? [String: Any]

            let fiveHourPct = fiveHour?["utilization"] as? Double ?? 0
            let sevenDayPct = sevenDay?["utilization"] as? Double ?? 0

            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            let fiveHourReset: Date? = {
                if let str = fiveHour?["resets_at"] as? String {
                    return isoFormatter.date(from: str) ?? ISO8601DateFormatter().date(from: str)
                }
                return nil
            }()
            let sevenDayReset: Date? = {
                if let str = sevenDay?["resets_at"] as? String {
                    return isoFormatter.date(from: str) ?? ISO8601DateFormatter().date(from: str)
                }
                return nil
            }()

            stats = UsageStats(
                fiveHourPercent: fiveHourPct,
                sevenDayPercent: sevenDayPct,
                fiveHourResetsAt: fiveHourReset,
                sevenDayResetsAt: sevenDayReset
            )
            cachedAt = Date()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Keychain Access

    /// Read OAuth access token from macOS Keychain
    private func getOAuthToken() -> String? {
        let serviceNames = ["Claude Code-credentials"]

        for serviceName in serviceNames {
            if let raw = readKeychainPassword(service: serviceName) {
                guard let data = raw.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

                // Token may be at top level or nested under "claudeAiOauth"
                let creds: [String: Any]
                if let nested = json["claudeAiOauth"] as? [String: Any] {
                    creds = nested
                } else {
                    creds = json
                }

                guard let accessToken = creds["accessToken"] as? String else { continue }

                // Check expiry (expiresAt is in milliseconds)
                if let expiresAt = creds["expiresAt"] as? Double {
                    if Date(timeIntervalSince1970: expiresAt / 1000) < Date() {
                        continue // Token expired
                    }
                }
                return accessToken
            }
        }
        return nil
    }

    /// Read a generic password from the Keychain
    private func readKeychainPassword(service: String) -> String? {
        // Use /usr/bin/security CLI (same as claude-hud) for reliability
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service, "-w"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else { return nil }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
}
