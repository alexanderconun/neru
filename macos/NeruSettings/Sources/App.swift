import AppKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct NeruSettingsApp: App {
    @StateObject private var neru = Neru()

    var body: some Scene {
        Window("Neru Settings", id: "settings") {
            ContentView()
                .environmentObject(neru)
                .frame(minWidth: 720, minHeight: 520)
        }
        .windowResizability(.contentMinSize)
    }
}

enum Page: String, CaseIterable, Identifiable {
    case general = "General", clicking = "Clicking", scrolling = "Scrolling"
    case ignored = "Ignored Apps", about = "About"
    var id: Self { self }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .clicking: "cursorarrow.click"
        case .scrolling: "scroll"
        case .ignored: "eye.slash"
        case .about: "info.circle"
        }
    }

    var color: Color {
        switch self {
        case .general, .ignored, .about: .gray
        case .clicking, .scrolling: .blue
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
                    Banner(text: "Could not find the neru binary. Install it or set NERU_BIN.")
                } else if !neru.running {
                    Banner(text: "Can't reach Neru: \(neru.notRunningReason)",
                           action: ("Start Neru", neru.start))
                }
                if let error = neru.error {
                    Banner(text: error, action: ("Dismiss", { neru.error = nil }))
                }
                switch page {
                case .general: GeneralPage()
                case .clicking: ClickingPage()
                case .scrolling: ScrollingPage()
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
    }
}

// MARK: pages

struct GeneralPage: View {
    @EnvironmentObject var neru: Neru

    var body: some View {
        Form {
            Section("Appearance") {
                LabeledContent("Theme") {
                    HStack(spacing: 14) {
                        ForEach(ThemePreset.all) { preset in
                            ThemeSwatch(preset: preset, selected: preset.matches(neru)) {
                                neru.setMany(preset.pairs)
                            }
                        }
                    }
                }
                SliderRow(title: "Label size", key: "hints.ui.font_size", range: 8...24, step: 1,
                          low: Image(systemName: "textformat.size.smaller"),
                          high: Image(systemName: "textformat.size.larger"))
            }
            Section("Application") {
                Toggle(isOn: Binding(get: { neru.launchAtLogin }, set: neru.setLaunchAtLogin)) {
                    HelpLabel("Launch on login", help: "Installs Neru as a launchd agent so it starts when you log in.")
                }
                SettingToggle(title: "Show menubar icon", key: "systray.enabled",
                              help: "Hiding it also hides the menu that opens this window. Run `neru` from a terminal to get back.")
                SettingToggle(title: "Hide labels in screen sharing", key: "general.hide_overlay_in_screen_share",
                              help: "Keeps labels out of screen recordings and shared screens.")
            }
            Section("Keyboard") {
                LayoutPicker()
            }
        }
        .formStyle(.grouped)
    }
}

struct ClickingPage: View {
    @EnvironmentObject var neru: Neru

    var body: some View {
        Form {
            Section("Clicking") {
                LabeledContent("Shortcut") { ShortcutRecorder(mode: "hints") }
                SettingToggle(title: "Mission Control", key: "hints.detect_mission_control",
                              help: "Show labels on windows and desktops while Mission Control is open.")
                SettingToggle(title: "Menu bar labels", key: "hints.include_menubar_hints",
                              help: "Also label items in the menu bar.")
                SettingToggle(title: "Dock labels", key: "hints.include_dock_hints",
                              help: "Also label items in the Dock.")
            }
            Section("Labels") {
                TextRow(title: "Label characters", key: "hints.hint_characters")
            }
            Section("Other modes") {
                LabeledContent { ShortcutRecorder(mode: "grid") } label: {
                    HelpLabel("Grid", help: "Click anywhere by picking a cell, even where there are no labels.")
                }
                LabeledContent { ShortcutRecorder(mode: "recursive_grid") } label: {
                    HelpLabel("Recursive grid", help: "Narrow down a point in a few keystrokes.")
                }
                LabeledContent { ShortcutRecorder(mode: "bisect") } label: {
                    HelpLabel("Bisect", help: "Halve the screen with each keystroke.")
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct ScrollingPage: View {
    @EnvironmentObject var neru: Neru

    var body: some View {
        Form {
            Section("Scrolling") {
                LabeledContent("Shortcut") { ShortcutRecorder(mode: "scroll") }
                SettingToggle(title: "Invert scrolling", key: "scroll.invert_scroll",
                              help: "Swap the direction of the scroll keys.")
            }
            Section("Speed") {
                SliderRow(title: "Scroll speed", key: "scroll.scroll_step", range: 10...300, step: 10,
                          low: Image(systemName: "tortoise"), high: Image(systemName: "hare"))
                SliderRow(title: "Dash speed", key: "scroll.scroll_step_half", range: 100...2000, step: 50,
                          low: Image(systemName: "tortoise"), high: Image(systemName: "hare"),
                          help: "How far half-page scrolls (d / u) move.")
            }
        }
        .formStyle(.grouped)
    }
}

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
                        Text("Ignored apps won't show Neru labels").foregroundStyle(.secondary)
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

struct AboutPage: View {
    @EnvironmentObject var neru: Neru

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)
            Text("Neru").font(.largeTitle.bold())
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
            Text("A fork of Neru by y3owk1n, MIT licensed.").font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: building blocks

struct HelpLabel: View {
    let title: String
    let help: String?

    init(_ title: String, help: String? = nil) {
        self.title = title
        self.help = help
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            if let help {
                Image(systemName: "questionmark.circle").foregroundStyle(.secondary).help(help)
            }
        }
    }
}

struct SettingToggle: View {
    @EnvironmentObject var neru: Neru
    let title: String
    let key: String
    var help: String?

    var body: some View {
        Toggle(isOn: Binding(get: { neru.bool(key) }, set: { neru.set(key, $0) })) {
            HelpLabel(title, help: help)
        }
        .toggleStyle(.switch)
    }
}

/// Commits on Return or when focus leaves, not on every keystroke.
struct TextRow: View {
    @EnvironmentObject var neru: Neru
    let title: String
    let key: String
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        LabeledContent(title) {
            TextField(title, text: $text)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240)
                .focused($focused)
                .onSubmit(commit)
                .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
        }
        .onAppear { text = neru.string(key) }
    }

    private func commit() {
        guard text != neru.string(key) else { return }
        neru.set(key, text)
        text = neru.string(key) // snap back if the daemon refused it
    }
}

/// Writes once the drag ends, so the daemon sees one change, not fifty.
struct SliderRow: View {
    @EnvironmentObject var neru: Neru
    let title: String
    let key: String
    let range: ClosedRange<Double>
    let step: Double
    let low: Image
    let high: Image
    var help: String?
    @State private var value = 0.0

    var body: some View {
        LabeledContent {
            HStack {
                low.foregroundStyle(.secondary)
                Slider(value: $value, in: range, step: step) { editing in
                    if !editing { neru.set(key, String(Int(value))) }
                }
                .frame(maxWidth: 260)
                high.foregroundStyle(.secondary)
            }
        } label: {
            HelpLabel(title, help: help)
        }
        .onAppear { value = min(max(neru.double(key), range.lowerBound), range.upperBound) }
    }
}

struct LayoutPicker: View {
    @EnvironmentObject var neru: Neru
    private let layouts = Neru.keyboardLayouts()

    var body: some View {
        Picker(selection: Binding(get: { neru.string("general.kb_layout_to_use") },
                                  set: { neru.set("general.kb_layout_to_use", $0) })) {
            Text("Automatic").tag("")
            ForEach(layouts, id: \.id) { Text($0.name).tag($0.id) }
        } label: {
            HelpLabel("Input source", help: "The keyboard layout shortcuts and label characters are read in. Automatic picks one with Latin letters.")
        }
    }
}

struct AppRow: View {
    let bundleID: String

    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        HStack {
            if let url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 24, height: 24)
            } else {
                Image(systemName: "app.dashed").frame(width: 24, height: 24)
            }
            VStack(alignment: .leading) {
                Text(url.map { FileManager.default.displayName(atPath: $0.path) } ?? bundleID)
                Text(bundleID).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct Banner: View {
    let text: String
    var action: (String, () -> Void)?

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text(text).lineLimit(3)
            Spacer()
            if let action { Button(action.0, action: action.1) }
        }
        .padding(10)
        .background(.yellow.opacity(0.12))
    }
}

// MARK: themes

struct ThemePreset: Identifiable {
    let name: String
    let light: [String: String]
    let dark: [String: String]
    var id: String { name }

    static let all = [
        ThemePreset(name: "Original",
                    light: ["surface": "#EEF2FF", "accent": "#465FBC", "accent_alt": "#0B2377", "on_accent_alt": "#F8FAFF", "text": "#17327A"],
                    dark: ["surface": "#0A1338", "accent": "#6E82D6", "accent_alt": "#8FA2F0", "on_accent_alt": "#081022", "text": "#E8EEFF"]),
        ThemePreset(name: "Classic",
                    light: ["surface": "#FFE066", "accent": "#C99A00", "accent_alt": "#000000", "on_accent_alt": "#FFE066", "text": "#1A1A1A"],
                    dark: ["surface": "#FFD43B", "accent": "#C99A00", "accent_alt": "#000000", "on_accent_alt": "#FFD43B", "text": "#111111"]),
        ThemePreset(name: "Graphite",
                    light: ["surface": "#F5F5F7", "accent": "#8E8E93", "accent_alt": "#1C1C1E", "on_accent_alt": "#FFFFFF", "text": "#1C1C1E"],
                    dark: ["surface": "#2C2C2E", "accent": "#636366", "accent_alt": "#F2F2F7", "on_accent_alt": "#1C1C1E", "text": "#F2F2F7"]),
    ]

    var pairs: [(String, String)] {
        light.map { ("theme.light.\($0.key)", $0.value) } + dark.map { ("theme.dark.\($0.key)", $0.value) }
    }

    func matches(_ neru: Neru) -> Bool {
        dark.allSatisfy { neru.string("theme.dark.\($0.key)").uppercased() == $0.value }
    }

    func colors(_ scheme: ColorScheme) -> (surface: Color, accent: Color, text: Color) {
        let palette = scheme == .dark ? dark : light
        return (Color(hex: palette["surface"]!), Color(hex: palette["accent"]!), Color(hex: palette["text"]!))
    }
}

struct ThemeSwatch: View {
    let preset: ThemePreset
    let selected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let colors = preset.colors(scheme)
        Button(action: action) {
            VStack(spacing: 6) {
                Text("AS")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(colors.text)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(colors.surface, in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(colors.accent, lineWidth: 1.5))
                    .frame(width: 72, height: 52)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Color.accentColor : .clear, lineWidth: 3))
                Text(preset.name).font(.caption).fontWeight(selected ? .semibold : .regular)
            }
        }
        .buttonStyle(.plain)
    }
}

extension Color {
    init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        self.init(red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }
}
