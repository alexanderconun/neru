import AppKit
import SwiftUI

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

/// The Settings window.
struct ContentView: View {
    @EnvironmentObject var neru: Neru
    @State private var page: Page

    init(page: Page = .general) {
        _page = State(initialValue: page)
    }

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
            .navigationTitle(page.rawValue)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            neru.refresh()
        }
    }
}
