import AppKit
import SwiftUI

@main
struct NeruSettingsApp: App {
    @StateObject private var neru = Neru()

    var body: some Scene {
        Window("\(Neru.appName) Settings", id: "settings") {
            ContentView()
                .environmentObject(neru)
                .frame(minWidth: 720, minHeight: 520)
        }
        .windowResizability(.contentMinSize)
    }
}

enum Page: String, CaseIterable, Identifiable {
    case general = "General", clicking = "Clicking", scrolling = "Scrolling", grid = "Grid"
    case perApp = "Per-App", ignored = "Ignored Apps", about = "About"
    var id: Self { self }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .clicking: "cursorarrow.click"
        case .scrolling: "scroll"
        case .grid: "square.grid.3x3"
        case .perApp: "macwindow.on.rectangle"
        case .ignored: "eye.slash"
        case .about: "info.circle"
        }
    }

    var color: Color {
        switch self {
        case .general, .ignored, .about: .gray
        case .clicking, .scrolling: .blue
        case .grid: .purple
        case .perApp: .orange
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var neru: Neru
    @State private var page: Page = .general

    var body: some View {
        NavigationSplitView {
            List(Page.allCases, selection: $page) { page in
                Label {
                    Text(page.rawValue)
                } icon: {
                    Image(systemName: page.icon)
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(page.color.gradient, in: RoundedRectangle(cornerRadius: 6))
                }
                .padding(.vertical, 2)
            }
            .navigationSplitViewColumnWidth(200)
        } detail: {
            VStack(spacing: 0) {
                if neru.binary == nil {
                    Banner(text: "Could not find \(Neru.appName). Install it in Applications, or set NERU_BIN.")
                } else if neru.needsAccessibility {
                    Banner(text: "\(Neru.appName) needs Accessibility permission. Turn \(Neru.appName) on in System Settings; it starts on its own once you do.",
                           action: ("Open System Settings", { NSWorkspace.shared.open(Neru.accessibilitySettingsURL) }))
                } else if !neru.running {
                    Banner(text: "Can't reach \(Neru.appName): \(neru.notRunningReason)",
                           action: ("Start \(Neru.appName)", neru.start))
                }
                if let error = neru.error {
                    Banner(text: error, action: ("Dismiss", { neru.error = nil }))
                }
                switch page {
                case .general: GeneralPage()
                case .clicking: ClickingPage()
                case .scrolling: ScrollingPage()
                case .grid: GridPage()
                case .perApp: PerAppPage()
                case .ignored: IgnoredAppsPage()
                case .about: AboutPage()
                }
            }
            .disabled(!neru.running && page != .about)
            .navigationTitle(page.rawValue)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            neru.refresh()
        }
        // While the daemon waits for permission, notice the moment it is granted.
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            if neru.needsAccessibility { neru.refresh() }
        }
    }
}
