// Self-checks for the update checker. Never calls GitHub: answers are canned.
import Foundation

func runUpdateTests() {
    // Release tags only; a `git describe` string or "dev" is a development build.
    for tag in ["v1.2.3", "v1.57.0-hk.4", "v10.0.12"] { assert(UpdateChecker.isRelease(tag), tag) }
    for tag in ["", "dev", "1.2.3", "v1.2", "v1.2.3-dirty", "v1.2.3-hk.", "nightly-5-g18748ae0-dirty", "v1.57.0-3-g6524e6ce"] {
        assert(!UpdateChecker.isRelease(tag), tag)
    }

    // The app's NeruBuildID wins; otherwise the tag from `neru --version`.
    let cli = "Neru version v1.2.3\nGit commit: abc\nBuild date: today"
    assert(UpdateChecker.installedVersion(buildID: "v1.2.4-hk.1", cliVersion: cli) == "v1.2.4-hk.1")
    assert(UpdateChecker.installedVersion(buildID: nil, cliVersion: cli) == "v1.2.3")
    assert(UpdateChecker.installedVersion(buildID: "", cliVersion: cli) == "v1.2.3")
    assert(UpdateChecker.installedVersion(buildID: nil, cliVersion: "") == "")
    // An error from a missing binary is not a version.
    assert(UpdateChecker.installedVersion(buildID: nil, cliVersion: "Could not find the neru binary") == "")

    // A trimmed /releases/latest payload.
    let release = Data("""
    {"url": "https://api.github.com/repos/alexanderconun/neru/releases/1", "tag_name": "v1.58.0-hk.1",
     "name": "v1.58.0-hk.1", "prerelease": false, "html_url": "https://github.com/alexanderconun/neru/releases/tag/v1.58.0-hk.1",
     "assets": [{"name": "neru-darwin-arm64.zip", "browser_download_url": "https://example.invalid/a.zip"}]}
    """.utf8)
    let page = URL(string: "https://github.com/alexanderconun/neru/releases/tag/v1.58.0-hk.1")!
    assert(UpdateChecker.status(installed: "v1.57.0-hk.4", data: release, code: 200, error: nil) == .available(tag: "v1.58.0-hk.1", page: page))
    assert(UpdateChecker.status(installed: "v1.58.0-hk.1", data: release, code: 200, error: nil) == .upToDate)
    // String equality, not ordering: a newer local build still differs from latest.
    assert(UpdateChecker.status(installed: "v9.0.0", data: release, code: 200, error: nil) == .available(tag: "v1.58.0-hk.1", page: page))

    // 404 means the repo has no release yet; other failures say why.
    let notFound = Data(#"{"message": "Not Found"}"#.utf8)
    assert(UpdateChecker.status(installed: "v1.0.0", data: notFound, code: 404, error: nil) == .noReleases)
    assert(UpdateChecker.status(installed: "v1.0.0", data: nil, code: nil, error: "The Internet connection appears to be offline.")
        == .failed("The Internet connection appears to be offline."))
    assert(UpdateChecker.status(installed: "v1.0.0", data: Data(), code: 403, error: nil) == .failed("GitHub answered with HTTP 403"))
    assert(UpdateChecker.status(installed: "v1.0.0", data: Data("<html>".utf8), code: 200, error: nil) == .failed("GitHub's answer could not be read"))
    // A development build is never compared, whatever GitHub says.
    assert(UpdateChecker.status(installed: "v1.57.0-3-g6524e6ce", data: release, code: 200, error: nil) == .development)

    // Automatic checks: off by default, then at most once per 24 h.
    let now = Date()
    assert(!UpdateChecker.isDue(enabled: false, last: nil, now: now))
    assert(UpdateChecker.isDue(enabled: true, last: nil, now: now))
    assert(!UpdateChecker.isDue(enabled: true, last: now.addingTimeInterval(-23 * 3600), now: now))
    assert(UpdateChecker.isDue(enabled: true, last: now.addingTimeInterval(-24 * 3600), now: now))
    print("update ok")
}
