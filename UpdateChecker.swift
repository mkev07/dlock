import AppKit

class UpdateChecker {

    static let shared = UpdateChecker()
    private init() {}

    private let apiURL = URL(string: "https://api.github.com/repos/mkev07/dlock/releases/latest")!

    // Called on launch — shows nothing if already up to date.
    func checkSilently() {
        fetch { [weak self] result in self?.handle(result, silent: true) }
    }

    // Called from "Check for Updates..." menu item — always shows a result.
    func checkAndNotify() {
        fetch { [weak self] result in self?.handle(result, silent: false) }
    }

    // MARK: - Private

    private struct Release {
        let version: String
        let pageURL: URL
    }

    private func fetch(completion: @escaping (Result<Release, Error>) -> Void) {
        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Dlock/1.0 (macOS; github.com/mkev07/dlock)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tag = json["tag_name"] as? String,
                      let htmlURL = json["html_url"] as? String,
                      let pageURL = URL(string: htmlURL) else {
                    completion(.failure(URLError(.cannotParseResponse)))
                    return
                }
                let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                completion(.success(Release(version: version, pageURL: pageURL)))
            }
        }.resume()
    }

    private func handle(_ result: Result<Release, Error>, silent: Bool) {
        switch result {
        case .failure(let error):
            guard !silent else { return }
            alert(title: "Update Check Failed", body: error.localizedDescription)

        case .success(let release):
            let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
            if isNewer(release.version, than: current) {
                NSApp.activate(ignoringOtherApps: true)
                let a = NSAlert()
                a.messageText = "Update Available"
                a.informativeText = "Dlock \(release.version) is available. You have version \(current)."
                a.addButton(withTitle: "Download")
                a.addButton(withTitle: "Later")
                if a.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(release.pageURL)
                }
            } else if !silent {
                alert(title: "You're Up to Date", body: "Dlock \(current) is the latest version.")
            }
        }
    }

    private func isNewer(_ latest: String, than current: String) -> Bool {
        latest.compare(current, options: .numeric) == .orderedDescending
    }

    private func alert(title: String, body: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = body
        a.addButton(withTitle: "OK")
        a.runModal()
    }
}
