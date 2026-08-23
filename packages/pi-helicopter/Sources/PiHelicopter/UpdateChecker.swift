import Foundation

struct AppVersion: Comparable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    static let zero = AppVersion(major: 0, minor: 0, patch: 0)

    init?(value: String) {
        let prefix = "pi-helicopter-v"
        let normalized = value.hasPrefix(prefix) ? String(value.dropFirst(prefix.count)) : value
        let components = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3,
              let major = Int(components[0]),
              let minor = Int(components[1]),
              let patch = Int(components[2]),
              major >= 0, minor >= 0, patch >= 0
        else { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    private init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    var description: String { "\(major).\(minor).\(patch)" }

    static func < (left: AppVersion, right: AppVersion) -> Bool {
        if left.major != right.major { return left.major < right.major }
        if left.minor != right.minor { return left.minor < right.minor }
        return left.patch < right.patch
    }
}

struct AppUpdate {
    static func latestVersion(data: Data) throws -> AppVersion {
        let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
        var latest: AppVersion?
        for release in releases where !release.draft && !release.prerelease {
            guard release.tagName.hasPrefix("pi-helicopter-v"),
                  let version = AppVersion(value: release.tagName)
            else { continue }
            if latest.map({ $0 < version }) ?? true { latest = version }
        }
        guard let latest else { throw UpdateCheckError.invalidResponse }
        return latest
    }
}

@MainActor
final class UpdateStore {
    private nonisolated static let releasesURL = URL(
        string: "https://api.github.com/repos/duarteocarmo/pi-tools/releases?per_page=20"
    )!
    private static let maximumAge: TimeInterval = 24 * 60 * 60
    private static let retryAge: TimeInterval = 5 * 60
    private static let lastCheckedKey = "updateLastCheckedAt"
    private static let latestVersionKey = "updateLatestVersion"

    private let currentVersion: AppVersion
    private let defaults: UserDefaults
    private var lastAttemptAt: Date?
    private(set) var availableVersion: AppVersion?
    private(set) var isChecking = false
    var onChange: (() -> Void)?

    init(
        currentVersion: String = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0.0.0",
        defaults: UserDefaults = .standard
    ) {
        self.currentVersion = AppVersion(value: currentVersion) ?? .zero
        self.defaults = defaults
        if let cached = defaults.string(forKey: Self.latestVersionKey),
           let version = AppVersion(value: cached),
           self.currentVersion < version
        {
            availableVersion = version
        }
        checkIfNeeded()
    }

    func checkIfNeeded(now: Date = Date()) {
        guard !isChecking else { return }
        if let lastChecked = defaults.object(forKey: Self.lastCheckedKey) as? Date,
           now.timeIntervalSince(lastChecked) < Self.maximumAge
        {
            return
        }
        if let lastAttemptAt, now.timeIntervalSince(lastAttemptAt) < Self.retryAge { return }

        isChecking = true
        lastAttemptAt = now
        Task { [weak self] in
            do {
                let version = try await Self.fetchLatestVersion()
                guard let self else { return }
                self.defaults.set(Date(), forKey: Self.lastCheckedKey)
                self.defaults.set(version.description, forKey: Self.latestVersionKey)
                self.availableVersion = self.currentVersion < version ? version : nil
                self.isChecking = false
                self.onChange?()
            } catch {
                guard let self else { return }
                self.isChecking = false
                self.onChange?()
            }
        }
    }

    private nonisolated static func fetchLatestVersion() async throws -> AppVersion {
        var request = URLRequest(url: releasesURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Pi-Helicopter", forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode)
        else { throw UpdateCheckError.invalidResponse }
        return try AppUpdate.latestVersion(data: data)
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let draft: Bool
    let prerelease: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case draft
        case prerelease
    }
}

private enum UpdateCheckError: Error {
    case invalidResponse
}
