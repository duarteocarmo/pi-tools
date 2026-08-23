import Darwin
import Foundation

enum SessionParser {
    static func parse(fileAt url: URL, size: Int, modifiedAt: TimeInterval) throws -> SessionStats {
        var session = SessionStats(
            path: url.path,
            size: size,
            modifiedAt: modifiedAt,
            sessionID: url.deletingPathExtension().lastPathComponent,
            project: url.deletingLastPathComponent().lastPathComponent,
            days: [:]
        )

        try readLines(fileAt: url) { line in
            guard !line.isEmpty else { return }

            if let role = lightweightRole(in: line),
               let timestamp = lightweightTimestamp(in: line),
               let date = Dates.parse(timestamp: timestamp) {
                let epoch = date.timeIntervalSince1970
                session.startedAt = min(session.startedAt ?? epoch, epoch)
                session.endedAt = max(session.endedAt ?? epoch, epoch)
                let dayKey = Dates.day.string(from: date)
                var day = session.days[dayKey] ?? DayStats()
                if role == "user" { day.userMessages += 1 } else { day.toolResults += 1 }
                session.days[dayKey] = day
                return
            }

            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any]
            else { return }

            if object["type"] as? String == "session" {
                if let id = object["id"] as? String, !id.isEmpty { session.sessionID = id }
                if let cwd = object["cwd"] as? String, !cwd.isEmpty {
                    session.project = URL(fileURLWithPath: cwd).lastPathComponent
                }
                return
            }

            guard object["type"] as? String == "message",
                  let message = object["message"] as? [String: Any],
                  let timestamp = object["timestamp"] as? String,
                  let date = Dates.parse(timestamp: timestamp)
            else { return }

            let epoch = date.timeIntervalSince1970
            session.startedAt = min(session.startedAt ?? epoch, epoch)
            session.endedAt = max(session.endedAt ?? epoch, epoch)

            let dayKey = Dates.day.string(from: date)
            var day = session.days[dayKey] ?? DayStats()
            let role = message["role"] as? String

            switch role {
            case "user":
                day.userMessages += 1
            case "toolResult":
                day.toolResults += 1
            case "assistant":
                day.assistantMessages += 1
                addAssistant(message: message, to: &day)
            default:
                break
            }

            addToolCalls(message: message, to: &day)
            session.days[dayKey] = day
        }

        return session
    }

    private static func addAssistant(message: [String: Any], to day: inout DayStats) {
        let model = message["model"] as? String
        if let model { day.modelMessages[model, default: 0] += 1 }

        guard let usage = message["usage"] as? [String: Any] else { return }
        day.tokens.input += integer(usage["input"])
        day.tokens.output += integer(usage["output"])
        day.tokens.cacheRead += integer(usage["cacheRead"])
        day.tokens.cacheWrite += integer(usage["cacheWrite"])

        guard let costs = usage["cost"] as? [String: Any] else { return }
        let cost = number(costs["total"])
        day.cost += cost
        if let model { day.modelCost[model, default: 0] += cost }
    }

    private static func addToolCalls(message: [String: Any], to day: inout DayStats) {
        guard let content = message["content"] as? [[String: Any]] else { return }

        for item in content {
            guard item["type"] as? String == "toolCall",
                  let name = item["name"] as? String
            else { continue }

            day.tools[name, default: 0] += 1
            guard name == "edit" || name == "write",
                  let arguments = item["arguments"] as? [String: Any],
                  let path = arguments["path"] as? String,
                  let language = Languages.name(forExtension: URL(fileURLWithPath: path).pathExtension)
            else { continue }

            var lines = 0
            if name == "write", let content = arguments["content"] as? String {
                lines = lineCount(content)
            } else if let newText = arguments["newText"] as? String {
                lines = lineCount(newText)
            } else if let edits = arguments["edits"] as? [[String: Any]] {
                lines = edits.reduce(0) { total, edit in
                    total + lineCount(edit["newText"] as? String ?? "")
                }
            }

            day.languageEdits[language, default: 0] += 1
            day.languageLines[language, default: 0] += lines
        }
    }

    private static let userRole = Data(#""message":{"role":"user""#.utf8)
    private static let toolResultRole = Data(#""message":{"role":"toolResult""#.utf8)
    private static let timestampPrefix = Data(#""timestamp":""#.utf8)

    private static func lightweightRole(in line: Data) -> String? {
        if line.range(of: userRole) != nil { return "user" }
        if line.range(of: toolResultRole) != nil { return "toolResult" }
        return nil
    }

    private static func lightweightTimestamp(in line: Data) -> String? {
        guard let prefix = line.range(of: timestampPrefix) else { return nil }
        let start = prefix.upperBound
        guard let end = line[start...].firstIndex(of: 0x22) else { return nil }
        return String(data: line[start..<end], encoding: .utf8)
    }

    private static func integer(_ value: Any?) -> Int {
        (value as? NSNumber)?.intValue ?? 0
    }

    private static func number(_ value: Any?) -> Double {
        (value as? NSNumber)?.doubleValue ?? 0
    }

    private static func lineCount(_ value: String) -> Int {
        guard !value.isEmpty else { return 0 }
        return value.utf8.reduce(value.hasSuffix("\n") ? 0 : 1) { count, byte in
            count + (byte == 0x0A ? 1 : 0)
        }
    }

    private static func readLines(fileAt url: URL, consume: (Data) -> Void) throws {
        guard let file = fopen(url.path, "rb") else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        defer { fclose(file) }

        var pointer: UnsafeMutablePointer<CChar>?
        var capacity = 0
        defer { free(pointer) }

        while true {
            let count = getline(&pointer, &capacity, file)
            guard count >= 0, let pointer else { break }
            let length = count > 0 && pointer[count - 1] == 0x0A ? count - 1 : count
            let line = Data(bytesNoCopy: pointer, count: length, deallocator: .none)
            autoreleasepool { consume(line) }
        }

        if ferror(file) != 0 {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }
}

enum Dates {
    static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let whole: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(timestamp: String) -> Date? {
        fractional.date(from: timestamp) ?? whole.date(from: timestamp)
    }
}

enum Languages {
    private static let names = [
        "c": "C", "cc": "C++", "cpp": "C++", "cs": "C#", "css": "CSS",
        "dart": "Dart", "ex": "Elixir", "exs": "Elixir", "go": "Go", "h": "C/C++",
        "hpp": "C++", "html": "HTML", "java": "Java", "js": "JavaScript",
        "jsx": "JavaScript", "kt": "Kotlin", "lua": "Lua", "m": "Objective-C",
        "md": "Markdown", "php": "PHP", "py": "Python", "r": "R", "rb": "Ruby",
        "rs": "Rust", "sh": "Shell", "sql": "SQL", "swift": "Swift", "toml": "TOML",
        "ts": "TypeScript", "tsx": "TypeScript", "vue": "Vue", "xml": "XML",
        "yaml": "YAML", "yml": "YAML", "zig": "Zig"
    ]

    static func name(forExtension extensionName: String) -> String? {
        names[extensionName.lowercased()]
    }
}
