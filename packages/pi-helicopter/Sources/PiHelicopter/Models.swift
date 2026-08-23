import Foundation

enum DateRange: String, CaseIterable, Codable, Hashable {
    case day
    case week
    case month
    case quarter
    case all

    var title: String {
        switch self {
        case .day: "Today"
        case .week: "7 days"
        case .month: "30 days"
        case .quarter: "90 days"
        case .all: "All time"
        }
    }

    var days: Int? {
        switch self {
        case .day: 1
        case .week: 7
        case .month: 30
        case .quarter: 90
        case .all: nil
        }
    }

    var shortTitle: String {
        switch self {
        case .day: "Today"
        case .week: "7d"
        case .month: "30d"
        case .quarter: "90d"
        case .all: "All"
        }
    }
}

enum DashboardTab: String, CaseIterable {
    case models
    case projects
    case languages
    case tools
    case tokens

    var title: String { rawValue.capitalized }

    var symbolName: String {
        switch self {
        case .models: "cpu"
        case .projects: "folder"
        case .languages: "chevron.left.forwardslash.chevron.right"
        case .tools: "wrench.and.screwdriver"
        case .tokens: "number"
        }
    }
}

struct TokenCounts: Codable, Equatable {
    var input = 0
    var output = 0
    var cacheRead = 0
    var cacheWrite = 0

    var total: Int { input + output + cacheRead + cacheWrite }

    static func += (left: inout TokenCounts, right: TokenCounts) {
        left.input += right.input
        left.output += right.output
        left.cacheRead += right.cacheRead
        left.cacheWrite += right.cacheWrite
    }
}

struct DayStats: Codable, Equatable {
    var cost = 0.0
    var tokens = TokenCounts()
    var userMessages = 0
    var assistantMessages = 0
    var toolResults = 0
    var modelCost: [String: Double] = [:]
    var modelMessages: [String: Int] = [:]
    var languageLines: [String: Int] = [:]
    var languageEdits: [String: Int] = [:]
    var tools: [String: Int] = [:]
}

struct SessionStats: Codable, Equatable {
    var path: String
    var size: Int
    var modifiedAt: TimeInterval
    var sessionID: String
    var project: String
    var startedAt: TimeInterval?
    var endedAt: TimeInterval?
    var days: [String: DayStats]

    var totalCost: Double { days.values.reduce(0) { $0 + $1.cost } }
}

struct StatsCache: Codable {
    let version: Int
    let sessions: [String: SessionStats]
}

struct NamedValue {
    let name: String
    let primary: Double
    let count: Int
}

struct Summary {
    var cost = 0.0
    var tokens = TokenCounts()
    var userMessages = 0
    var assistantMessages = 0
    var toolResults = 0
    var sessionCount = 0
    var daysActive = 0
    var models: [NamedValue] = []
    var projects: [NamedValue] = []
    var languages: [NamedValue] = []
    var tools: [NamedValue] = []
    var dailySpend: [(day: String, cost: Double)] = []

    var messageCount: Int { userMessages + assistantMessages }
}

enum Format {
    static func count(_ value: Int) -> String {
        compact(Double(value))
    }

    static func modelName(_ name: String) -> String {
        var result = name
        if result.hasPrefix("claude-") {
            result = "Claude " + result.dropFirst("claude-".count)
        }
        result = result.replacingOccurrences(of: "opus", with: "Opus")
        result = result.replacingOccurrences(of: "sonnet", with: "Sonnet")
        result = result.replacingOccurrences(of: "haiku", with: "Haiku")
        return result
    }

    static func compact(_ value: Double) -> String {
        let magnitude: (divisor: Double, suffix: String)
        switch abs(value) {
        case 1_000_000_000...: magnitude = (1_000_000_000, "B")
        case 1_000_000...: magnitude = (1_000_000, "M")
        case 1_000...: magnitude = (1_000, "K")
        default: return String(format: "%.0f", value)
        }

        let scaled = value / magnitude.divisor
        let digits = scaled >= 100 ? 0 : scaled >= 10 ? 1 : 2
        return String(format: "%.*f%@", digits, scaled, magnitude.suffix)
    }
}
