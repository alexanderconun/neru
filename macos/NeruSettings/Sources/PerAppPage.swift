import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Overrides for one app at a time, kept in config.toml (PerApp.swift).
struct PerAppPage: View {
    @EnvironmentObject var neru: Neru
    @State private var editing: EditedApp?

    var body: some View {
        Form {
            Section {
                let apps = neru.perAppIDs
                if apps.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "macwindow.on.rectangle").font(.system(size: 36)).foregroundStyle(.secondary)
                        Text("No per-app settings").font(.headline)
                        Text("Change how \(Neru.appName) labels and scrolls in one app").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
                ForEach(apps, id: \.self) { bundleID in
                    HStack {
                        AppRow(bundleID: bundleID)
                        Spacer()
                        Button("Edit") { editing = EditedApp(id: bundleID) }
                        Button(role: .destructive) {
                            neru.removeAppConfigs(bundleID)
                        } label: { Image(systemName: "minus.circle.fill") }
                            .buttonStyle(.borderless)
                    }
                }
                HStack {
                    Spacer()
                    Button(action: addApp) { Label("Add App", systemImage: "plus") }
                        .buttonStyle(.borderedProminent)
                    Spacer()
                }
            } header: {
                Text("Per-App Settings")
            } footer: {
                Text("These replace the general settings while the app is in front.").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editing) { AppEditor(bundleID: $0.id).environmentObject(neru) }
    }

    /// Opens the editor for the picked app; nothing is written until a field changes.
    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let id = panel.url.flatMap({ Bundle(url: $0)?.bundleIdentifier }) else { return }
        editing = EditedApp(id: neru.perAppIDs.first { $0.lowercased() == id.lowercased() } ?? id)
    }
}

private struct EditedApp: Identifiable {
    let id: String
}

private struct AppEditor: View {
    @EnvironmentObject var neru: Neru
    @Environment(\.dismiss) private var dismiss
    let bundleID: String

    private static let strategies = [("axtree", "Accessibility"), ("vision", "Text recognition"), ("contour", "Shapes")]

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section { AppRow(bundleID: bundleID) }
                Section("Clicking") {
                    Picker(selection: Binding(get: { neru.appSetting("hints", bundleID, "strategy") as? String ?? "" },
                                              set: { neru.setAppSetting("hints", bundleID, "strategy", $0.isEmpty ? nil : $0) })) {
                        let global = neru.string("hints.strategy")
                        Text("Default (\(Self.strategies.first { $0.0 == global }?.1 ?? global))").tag("")
                        ForEach(Self.strategies, id: \.0) { Text($0.1).tag($0.0) }
                    } label: {
                        HelpLabel("Label detection", help: "How \(Neru.appName) finds what to label. Accessibility reads the app's interface; Text recognition and Shapes look at the screen image, for apps that hide their interface.")
                    }
                    triState("Skip clickability check", "ignoreClickableCheck", global: "hints.ignore_clickable_check",
                             help: "Label every element the app reports, not only those that look clickable.")
                    triState("Visibility check", "visibleCheckEnabled", global: "hints.visible_check_enabled",
                             help: "Drop labels for elements hidden behind others. Slower, but fewer stray labels.")
                    CommitField(title: "Extra clickable roles", prompt: "None",
                                help: "More roles to label in this app, separated by commas: names like button, or native ones like ax:AXCell.",
                                saved: (neru.appSetting("hints", bundleID, "additionalClickable") as? [String] ?? []).joined(separator: ", ")) { text in
                        let roles = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                        neru.setAppSetting("hints", bundleID, "additionalClickable", roles.isEmpty ? nil : roles)
                        return true
                    }
                }
                Section("Scrolling") {
                    stepField("Scroll step", "scrollStep", global: "scroll.scroll_step", help: "How far one scroll key press moves in this app.")
                    stepField("Half-page step", "scrollStepHalf", global: "scroll.scroll_step_half", help: "How far half-page scrolls (d / u) move in this app.")
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 520, height: 500)
    }

    /// Default / On / Off, where Default leaves the key out of the file.
    private func triState(_ title: String, _ key: String, global: String, help: String) -> some View {
        Picker(selection: Binding<Bool?>(get: { neru.appSetting("hints", bundleID, key) as? Bool },
                                         set: { neru.setAppSetting("hints", bundleID, key, $0) })) {
            Text("Default (\(neru.bool(global) ? "On" : "Off"))").tag(nil as Bool?)
            Text("On").tag(true as Bool?)
            Text("Off").tag(false as Bool?)
        } label: {
            HelpLabel(title, help: help)
        }
    }

    /// A whole number of 1 or more; empty means the general setting.
    private func stepField(_ title: String, _ key: String, global: String, help: String) -> some View {
        CommitField(title: title, prompt: "Default (\(Int(neru.double(global))))", help: help,
                    saved: (neru.appSetting("scroll", bundleID, key) as? Int).map(String.init) ?? "") { text in
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard trimmed.isEmpty || (Int(trimmed) ?? 0) >= 1 else { return false }
            neru.setAppSetting("scroll", bundleID, key, Int(trimmed))
            return true
        }
    }
}

/// Like TextRow, but for a value that is not one `config set` key. `commit`
/// returns false to refuse the text, which then snaps back.
private struct CommitField: View {
    let title: String
    let prompt: String
    let help: String
    let saved: String
    let commit: (String) -> Bool
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        LabeledContent {
            TextField(title, text: $text, prompt: Text(prompt))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240)
                .focused($focused)
                .onSubmit(save)
                .onChange(of: focused) { _, isFocused in if !isFocused { save() } }
        } label: {
            HelpLabel(title, help: help)
        }
        .onAppear { text = saved }
        .onChange(of: saved) { _, value in if !focused { text = value } }
        .onDisappear(perform: save) // Done while still typing
    }

    private func save() {
        guard text != saved else { return }
        if !commit(text) { text = saved }
    }
}
