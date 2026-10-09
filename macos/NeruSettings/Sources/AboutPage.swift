import AppKit
import SwiftUI

struct AboutPage: View {
    @EnvironmentObject var neru: Neru
    @ObservedObject private var updates = UpdateChecker.shared
    @AppStorage(UpdateChecker.autoCheckKey) private var autoCheck = false

    var body: some View {
        let installed = UpdateChecker.installedVersion(cliVersion: neru.version)
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)
            Text(Neru.appName).font(.largeTitle.bold())
            Text(installed.isEmpty ? "Version unknown" : "Version \(installed)")
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        HelpLabel("Check for updates automatically",
                                  help: "Checks once a day when this page opens. The only network request \(Neru.appName) makes is this one GET to GitHub for the latest release; it sends nothing about you.")
                        Spacer()
                        Toggle("Check for updates automatically", isOn: $autoCheck).labelsHidden().toggleStyle(.switch)
                    }
                    HStack {
                        status
                        Spacer()
                        Button("Check Now") { updates.check(installed: installed) }
                            .disabled(updates.status == .checking)
                    }
                }
                .padding(4)
            }
            .frame(maxWidth: 440)
            HStack {
                Link(destination: URL(string: "https://github.com/alexanderconun/neru")!) {
                    Label("Source", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Link(destination: URL(string: "https://github.com/alexanderconun/neru/blob/main/docs/reference/configuration.md")!) {
                    Label("Config docs", systemImage: "book")
                }
                Link(destination: URL(string: "https://github.com/alexanderconun/neru/issues")!) {
                    Label("Report a bug", systemImage: "ladybug")
                }
            }
            .buttonStyle(.bordered)
            Text("Based on Neru by y3owk1n, MIT licensed.").font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { updates.checkIfDue(installed: installed) }
        .onChange(of: autoCheck) { _, on in if on { updates.checkIfDue(installed: installed) } }
    }

    @ViewBuilder private var status: some View {
        switch updates.status {
        case .idle:
            Text("Not checked yet").foregroundStyle(.secondary)
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking…").foregroundStyle(.secondary)
            }
        case .upToDate:
            Label("\(Neru.appName) is up to date", systemImage: "checkmark.circle.fill")
        case let .available(tag, page):
            HStack {
                Label("\(tag) is available", systemImage: "arrow.down.circle.fill")
                Button("Download") { NSWorkspace.shared.open(page) }.buttonStyle(.borderedProminent)
            }
        case .noReleases:
            Text("No releases yet").foregroundStyle(.secondary)
        case let .failed(reason):
            Label("Couldn't check: \(reason)", systemImage: "exclamationmark.triangle").lineLimit(2)
        case .development:
            Text("Development build, not compared with releases").foregroundStyle(.secondary)
        }
    }
}
