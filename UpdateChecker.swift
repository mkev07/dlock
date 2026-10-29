import AppKit
import Combine

final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    enum State: Equatable {
        case idle, checking
        case upToDate(String)
        case available(String, URL)
        case unavailable
        case failed(String)

        var title: String {
            switch self {
            case .idle: return "Dlock updates"
            case .checking: return "Checking for updates…"
            case .upToDate: return "You’re up to date"
            case .available(let version, _): return "Dlock \(version) is available"
            case .unavailable: return "Release information unavailable"
            case .failed: return "Update check failed"
            }
        }
        var detail: String {
            switch self {
            case .idle: return "Check GitHub for a newer version."
            case .checking: return "Contacting GitHub…"
            case .upToDate(let version): return "Installed version \(version)."
            case .available: return "Open the release page to download manually."
            case .unavailable: return "GitHub could not find an accessible latest release."
            case .failed(let message): return message
            }
        }
        var actionTitle: String {
            switch self {
            case .available: return "View release"
            case .checking: return "Checking…"
            case .failed, .unavailable: return "Retry"
            default: return "Check"
            }
        }
    }

    typealias Completion = (Data?, URLResponse?, Error?) -> Void
    private let load: (URLRequest, @escaping Completion) -> Void
    private let currentVersion: String
    @Published private(set) var state: State = .idle {
        didSet { onStateChange?() }
    }
    var onStateChange: (() -> Void)?

    init(currentVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
         load: @escaping (URLRequest, @escaping Completion) -> Void = { request, completion in
             URLSession.shared.dataTask(with: request, completionHandler: completion).resume()
         }) {
        self.currentVersion = currentVersion
        self.load = load
    }

    func checkSilently() { check() }

    func check() {
        guard state != .checking else { return }
        state = .checking
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/mkev07/dlock/releases/latest")!)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Dlock (macOS)", forHTTPHeaderField: "User-Agent")
        load(request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.state = Self.evaluate(data: data, response: response, error: error, currentVersion: self.currentVersion)
            }
        }
    }

    func performAction() {
        if case .available(_, let url) = state {
            if !NSWorkspace.shared.open(url) {
                state = .failed("Could not open the release page. Check your default browser and retry.")
            }
        } else { check() }
    }

    static func evaluate(data: Data?, response: URLResponse?, error: Error?, currentVersion: String) -> State {
        if let error { return .failed(error.localizedDescription) }
        guard let response = response as? HTTPURLResponse else {
            return .failed("GitHub returned an invalid response. Try again.")
        }
        switch response.statusCode {
        case 404: return .unavailable
        case 403, 429: return .failed("GitHub refused the request or its rate limit was reached. Try again later.")
        case 200: break
        default: return .failed("GitHub returned HTTP \(response.statusCode). Try again later.")
        }
        guard let data, let release = try? JSONDecoder().decode(Release.self, from: data),
              !release.draft, !release.prerelease,
              let latest = versionParts(release.tagName), let current = versionParts(currentVersion),
              let url = URL(string: release.htmlURL),
              url.scheme == "https", url.host == "github.com",
              url.user == nil, url.password == nil, url.port == nil,
              url.path.hasPrefix("/mkev07/dlock/releases/tag/") else {
            return .failed("GitHub returned unrecognized release information. Try again later.")
        }
        for index in 0..<max(latest.count, current.count) {
            let latestPart = index < latest.count ? latest[index] : 0
            let currentPart = index < current.count ? current[index] : 0
            if latestPart > currentPart {
                let version = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
                return .available(version, url)
            }
            if latestPart < currentPart { return .upToDate(currentVersion) }
        }
        return .upToDate(currentVersion)
    }

    private static func versionParts(_ version: String) -> [Int]? {
        let value = version.hasPrefix("v") ? String(version.dropFirst()) : version
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(components.count), components.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0 >= "0" && $0 <= "9" } }) else { return nil }
        let numbers = components.compactMap { Int($0) }
        return numbers.count == components.count ? numbers : nil
    }

    private struct Release: Decodable {
        let tagName: String
        let htmlURL: String
        let draft: Bool
        let prerelease: Bool
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case draft, prerelease
        }
    }
}
