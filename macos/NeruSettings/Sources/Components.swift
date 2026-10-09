import AppKit
import SwiftUI

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
        .onChange(of: neru.string(key)) { _, saved in if !focused { text = saved } } // snaps back if refused
    }

    private func commit() {
        guard text != neru.string(key) else { return }
        neru.set(key, text)
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
                    if !editing { neru.set(key, String(Int(value)), local: Int(value)) }
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
