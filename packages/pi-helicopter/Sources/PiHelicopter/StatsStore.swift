import Darwin
import Foundation

struct ScanResult {
    let sessions: [String: SessionStats]
    let changed: Bool
}

struct SessionScanner {
    let sessionsURL: URL
    let cacheURL: URL

    func scan(force: Bool) throws -> ScanResult {
        let cached = force ? [:] : loadCache()
        var sessions: [String: SessionStats] = [:]
        var changed = force
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: sessionsURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { return ScanResult(sessions: cached, changed: false) }

        guard let files = FileManager.default.enumerator(
            at: sessionsURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return ScanResult(sessions: cached, changed: false) }

        for case let url as URL in files where url.pathExtension == "jsonl" {
            let values = try url.resourceValues(forKeys: Set(keys))
            guard values.isRegularFile == true else { continue }

            let size = values.fileSize ?? 0
            let modifiedAt = values.contentModificationDate?.timeIntervalSince1970 ?? 0
            if let previous = cached[url.path],
               previous.size == size,
               previous.modifiedAt == modifiedAt {
                sessions[url.path] = previous
                continue
            }

            do {
                sessions[url.path] = try SessionParser.parse(
                    fileAt: url,
                    size: size,
                    modifiedAt: modifiedAt
                )
                changed = true
            } catch {
                if let previous = cached[url.path] { sessions[url.path] = previous }
            }
        }

        if sessions.count != cached.count { changed = true }
        if changed { try saveCache(sessions: sessions) }
        return ScanResult(sessions: sessions, changed: changed)
    }

    private func loadCache() -> [String: SessionStats] {
        guard let data = try? Data(contentsOf: cacheURL),
              let cache = try? PropertyListDecoder().decode(StatsCache.self, from: data),
              cache.version == 1
        else { return [:] }
        return cache.sessions
    }

    private func saveCache(sessions: [String: SessionStats]) throws {
        try FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(StatsCache(version: 1, sessions: sessions))
        try data.write(to: cacheURL, options: .atomic)
    }
}

enum Summarizer {
    static func summarize(sessions: [String: SessionStats], range: DateRange) -> Summary {
        var summary = Summary()
        var activeDays = Set<String>()
        var models: [String: (cost: Double, count: Int)] = [:]
        var projects: [String: (cost: Double, sessions: Set<String>)] = [:]
        var languages: [String: (lines: Int, edits: Int)] = [:]
        var tools: [String: Int] = [:]
        var dailySpend: [String: Double] = [:]
        let cutoff = cutoffKey(for: range)

        for session in sessions.values {
            var sessionIsActive = false
            var sessionCost = 0.0

            for (dayKey, day) in session.days where cutoff.map({ dayKey >= $0 }) ?? true {
                sessionIsActive = true
                sessionCost += day.cost
                summary.cost += day.cost
                summary.tokens += day.tokens
                summary.userMessages += day.userMessages
                summary.assistantMessages += day.assistantMessages
                summary.toolResults += day.toolResults
                activeDays.insert(dayKey)
                dailySpend[dayKey, default: 0] += day.cost

                for (name, cost) in day.modelCost { models[name, default: (0, 0)].cost += cost }
                for (name, count) in day.modelMessages { models[name, default: (0, 0)].count += count }
                for (name, lines) in day.languageLines { languages[name, default: (0, 0)].lines += lines }
                for (name, edits) in day.languageEdits { languages[name, default: (0, 0)].edits += edits }
                for (name, count) in day.tools { tools[name, default: 0] += count }
            }

            guard sessionIsActive else { continue }
            summary.sessionCount += 1
            var project = projects[session.project, default: (0, [])]
            project.cost += sessionCost
            project.sessions.insert(session.sessionID)
            projects[session.project] = project

        }

        summary.daysActive = activeDays.count
        summary.models = models.map {
            NamedValue(name: $0.key, primary: $0.value.cost, count: $0.value.count)
        }.sorted { $0.primary == $1.primary ? $0.count > $1.count : $0.primary > $1.primary }
        summary.projects = projects.map {
            NamedValue(name: $0.key, primary: $0.value.cost, count: $0.value.sessions.count)
        }.sorted { $0.primary > $1.primary }
        summary.languages = languages.map {
            NamedValue(name: $0.key, primary: Double($0.value.lines), count: $0.value.edits)
        }.sorted { $0.primary == $1.primary ? $0.count > $1.count : $0.primary > $1.primary }
        summary.tools = tools.map {
            NamedValue(name: $0.key, primary: Double($0.value), count: $0.value)
        }.sorted { $0.count > $1.count }
        summary.dailySpend = dailySpend.map { (day: $0.key, cost: $0.value) }.sorted { $0.day < $1.day }
        return summary
    }

    private static func cutoffKey(for range: DateRange) -> String? {
        guard let days = range.days,
              let cutoff = Calendar.current.date(
                byAdding: .day,
                value: -(days - 1),
                to: Calendar.current.startOfDay(for: Date())
              )
        else { return nil }
        return Dates.day.string(from: cutoff)
    }
}

@MainActor
final class StatsStore {
    private var summaries: [DateRange: Summary]
    private var hasLoadedStats: Bool
    private(set) var isRefreshing = false
    private(set) var lastUpdated: Date?
    private(set) var error: String?
    var onChange: (() -> Void)?

    var selectedRange: DateRange {
        didSet { UserDefaults.standard.set(selectedRange.rawValue, forKey: "selectedRange") }
    }

    private let scanner: SessionScanner
    private let queue = DispatchQueue(label: "com.duarteocarmo.pi-helicopter.scan", qos: .utility)

    init(
        sessionsURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".pi/agent/sessions"),
        cacheURL: URL? = nil,
        sessions: [String: SessionStats] = [:]
    ) {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        scanner = SessionScanner(
            sessionsURL: sessionsURL,
            cacheURL: cacheURL ?? caches.appendingPathComponent("com.duarteocarmo.pi-helicopter/stats.plist")
        )
        summaries = Dictionary(uniqueKeysWithValues: DateRange.allCases.map {
            ($0, Summarizer.summarize(sessions: sessions, range: $0))
        })
        hasLoadedStats = !sessions.isEmpty
        selectedRange = DateRange(
            rawValue: UserDefaults.standard.string(forKey: "selectedRange") ?? ""
        ) ?? .week
    }

    func refresh(force: Bool = false) {
        guard !isRefreshing else { return }
        isRefreshing = true
        error = nil
        onChange?()

        let scanner = scanner
        let needsInitialSummary = !hasLoadedStats
        queue.async { [weak self] in
            do {
                let summaries: [DateRange: Summary]? = try autoreleasepool {
                    let result = try scanner.scan(force: force)
                    guard needsInitialSummary || result.changed else { return nil }
                    return Dictionary(uniqueKeysWithValues: DateRange.allCases.map {
                        ($0, Summarizer.summarize(sessions: result.sessions, range: $0))
                    })
                }
                if summaries != nil { malloc_zone_pressure_relief(nil, 0) }
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let summaries { self.summaries = summaries }
                    self.hasLoadedStats = true
                    self.lastUpdated = Date()
                    self.isRefreshing = false
                    self.onChange?()
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.error = error.localizedDescription
                    self.isRefreshing = false
                    self.onChange?()
                }
            }
        }
    }

    func summary(for range: DateRange) -> Summary {
        summaries[range] ?? Summary()
    }
}
