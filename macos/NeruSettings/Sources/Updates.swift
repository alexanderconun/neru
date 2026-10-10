import Foundation

/// Asks GitHub for the fork's latest release. That one GET is the only
/// network request the app makes, and it carries nothing about the user.
/// Shared so the result survives switching pages.
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/alexanderconun/neru/releases/latest")!
    /// UserDefaults keys. Automatic checks are off until the user turns them on.
    static let autoCheckKey = "checkForUpdatesAutomatically"
    static let lastCheckKey = "lastUpdateCheck"

    enum Status: Equatable {
        case idle, checking, upToDate, noReleases, development
        case available(tag: String, page: URL)
        case failed(String)
    }

    @Published var status = Status.idle

    /// A development build has nothing to compare, so it never asks.
    func check(installed: String) {
        guard Self.isRelease(installed) else { status = .development; return }
        status = .checking
        UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
        var request = URLRequest(url: Self.latestReleaseURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { data, response, error in
            let status = Self.status(installed: installed, data: data,
                                     code: (response as? HTTPURLResponse)?.statusCode,
                                     error: error?.localizedDescription)
            DispatchQueue.main.async { self.status = status }
        }.resume()
    }

    /// Checks when automatic checks are on and the last one is a day old.
    // ponytail: runs when the About page appears, where the result shows;
    // checking at launch and badging the sidebar would need App.swift.
    func checkIfDue(installed: String) {
        let defaults = UserDefaults.standard
        if Self.isDue(enabled: defaults.bool(forKey: Self.autoCheckKey),
                      last: defaults.object(forKey: Self.lastCheckKey) as? Date, now: Date()) {
            check(installed: installed)
        }
    }

    /// NeruBuildID of the app this window ships in
    /// (<App>.app/Contents/Helpers/Homekey Settings.app), else the tag in the
    /// first line of `neru --version` ("Neru version <tag>"), else "".
    static func installedVersion(cliVersion: String) -> String {
        let app = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let buildID = app.pathExtension == "app" ? Bundle(url: app)?.object(forInfoDictionaryKey: "NeruBuildID") as? String : nil
        return installedVersion(buildID: buildID, cliVersion: cliVersion)
    }

    // MARK: pure helpers (covered by Tests/UpdateTests.swift)

    static func installedVersion(buildID: String?, cliVersion: String) -> String {
        if let buildID, !buildID.isEmpty { return buildID }
        let first = cliVersion.components(separatedBy: "\n")[0]
        let prefix = "Neru version "
        // Anything else is an error message (no binary), not a version.
        return first.hasPrefix(prefix) ? String(first.dropFirst(prefix.count)) : ""
    }

    /// Release tags look like v1.2.3 or v1.2.3-hk.4; anything else (a
    /// `git describe` string, "dev") is a development build.
    static func isRelease(_ version: String) -> Bool {
        version.range(of: #"^v\d+\.\d+\.\d+(-hk\.\d+)?$"#, options: .regularExpression) != nil
    }

    static func isDue(enabled: Bool, last: Date?, now: Date) -> Bool {
        guard enabled else { return false }
        guard let last else { return true }
        return now.timeIntervalSince(last) >= 24 * 60 * 60
    }

    /// What GitHub's answer means for `installed`. Tags are compared by
    /// string equality: the build id is the tag it was built from.
    static func status(installed: String, data: Data?, code: Int?, error: String?) -> Status {
        guard isRelease(installed) else { return .development }
        if let error { return .failed(error) }
        if code == 404 { return .noReleases }
        guard let code, code == 200 else { return .failed("GitHub answered with HTTP \(code.map(String.init) ?? "nothing")") }
        guard let json = data.flatMap({ Neru.json(String(decoding: $0, as: UTF8.self)) }),
              let tag = json["tag_name"] as? String, !tag.isEmpty,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:))
        else { return .failed("GitHub's answer could not be read") }
        return tag == installed ? .upToDate : .available(tag: tag, page: page)
    }
}
