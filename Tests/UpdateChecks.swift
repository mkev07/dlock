import AppKit

@main struct UpdateChecks {
    static func main() {
        var failures = 0
        func check(_ condition: Bool, _ name: String) {
            print("\(condition ? "PASS" : "FAIL"): \(name)")
            if !condition { failures += 1 }
        }
        let releaseURL = URL(string: "https://github.com/mkev07/dlock/releases/tag/v1.2.0")!
        func evaluate(_ status: Int = 200, tag: String = "v1.2.0", current: String = "1.0.0", url: String? = nil, draft: Bool = false, prerelease: Bool = false) -> UpdateChecker.State {
            let data = try! JSONSerialization.data(withJSONObject: ["tag_name": tag, "html_url": url ?? releaseURL.absoluteString, "draft": draft, "prerelease": prerelease])
            let response = HTTPURLResponse(url: releaseURL, statusCode: status, httpVersion: nil, headerFields: nil)
            return UpdateChecker.evaluate(data: data, response: response, error: nil, currentVersion: current)
        }
        func isFailure(_ state: UpdateChecker.State) -> Bool {
            if case .failed = state { return true }
            return false
        }
        check(evaluate() == .available("1.2.0", releaseURL), "newer release available")
        check(evaluate(tag: "1.0.0") == .upToDate("1.0.0"), "same version current")
        check(evaluate(tag: "v1.0") == .upToDate("1.0.0"), "trailing zero versions equivalent")
        check(evaluate(tag: "1.9.0", current: "1.10.0") == .upToDate("1.10.0"), "numeric comparison")
        check(evaluate(404) == .unavailable, "404 is not up to date")
        for status in [403, 429, 500] { check(isFailure(evaluate(status)), "HTTP \(status) failure") }
        for tag in ["", "latest", "1..0", "1.2.0-beta", "999999999999999999999999999999"] {
            check(isFailure(evaluate(tag: tag)), "reject invalid version \(tag)")
        }
        check(isFailure(evaluate(current: "")), "missing installed version not assumed current")
        check(isFailure(evaluate(draft: true)), "draft rejected")
        check(isFailure(evaluate(prerelease: true)), "prerelease rejected")
        for url in ["http://github.com/mkev07/dlock/releases/tag/v2", "https://example.com/release", "https://github.com/other/app/releases/tag/v2", "https://user@github.com/mkev07/dlock/releases/tag/v2"] {
            check(isFailure(evaluate(url: url)), "unsafe release URL rejected")
        }
        check(isFailure(UpdateChecker.evaluate(data: Data("{}".utf8), response: HTTPURLResponse(url: releaseURL, statusCode: 200, httpVersion: nil, headerFields: nil), error: nil, currentVersion: "1.0.0")), "malformed payload rejected")
        check(isFailure(UpdateChecker.evaluate(data: nil, response: nil, error: URLError(.timedOut), currentVersion: "1.0.0")), "timeout failure")
        var requests = 0
        var pending: UpdateChecker.Completion?
        let checker = UpdateChecker(currentVersion: "1.0.0", load: { request, completion in
            requests += 1
            check(request.timeoutInterval == 20, "bounded request timeout")
            pending = completion
        })
        checker.check()
        checker.check()
        check(checker.state == .checking && requests == 1, "duplicate checks coalesced")
        pending?(nil, HTTPURLResponse(url: releaseURL, statusCode: 404, httpVersion: nil, headerFields: nil), nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        check(checker.state == .unavailable && checker.state.actionTitle == "Retry", "unavailable state offers retry")
        checker.check()
        check(requests == 2 && checker.state == .checking, "retry starts fresh request")
        exit(failures == 0 ? 0 : 1)
    }
}
