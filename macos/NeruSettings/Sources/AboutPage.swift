import AppKit
import SwiftUI

struct AboutPage: View {
    @EnvironmentObject var neru: Neru

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)
            Text(Neru.appName).font(.largeTitle.bold())
            Text(neru.version.isEmpty ? "Version unknown" : neru.version).foregroundStyle(.secondary)
            HStack {
                Link(destination: URL(string: "https://github.com/alexanderconun/neru")!) {
                    Label("Source", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Link(destination: URL(string: "https://github.com/y3owk1n/neru/blob/main/docs/reference/configuration.md")!) {
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
    }
}
