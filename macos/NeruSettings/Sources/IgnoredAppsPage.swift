import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct IgnoredAppsPage: View {
    @EnvironmentObject var neru: Neru
    private let key = "general.excluded_apps"

    var body: some View {
        Form {
            Section("Ignored Applications") {
                let apps = neru.strings(key)
                if apps.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "eye.slash").font(.system(size: 36)).foregroundStyle(.secondary)
                        Text("No apps ignored").font(.headline)
                        Text("Ignored apps won't show \(Neru.appName) labels").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
                ForEach(apps, id: \.self) { bundleID in
                    HStack {
                        AppRow(bundleID: bundleID)
                        Spacer()
                        Button(role: .destructive) {
                            neru.set(key, apps.filter { $0 != bundleID })
                        } label: { Image(systemName: "minus.circle.fill") }
                            .buttonStyle(.borderless)
                    }
                }
                HStack {
                    Spacer()
                    Button { selectApps(current: apps) } label: { Label("Select Apps", systemImage: "plus") }
                        .buttonStyle(.borderedProminent)
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
    }

    private func selectApps(current: [String]) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }
        let picked = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
        let merged = current + picked.filter { !current.contains($0) }
        if merged != current { neru.set(key, merged) }
    }
}
