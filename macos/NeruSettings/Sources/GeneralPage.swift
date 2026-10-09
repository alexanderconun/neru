import SwiftUI

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
                    HelpLabel("Launch on login", help: "Starts \(Neru.appName) when you log in.")
                }
                SettingToggle(title: "Show menubar icon", key: "systray.enabled",
                              help: "Hiding it also hides the menu that opens this window. Open \(Neru.appName) from Applications again to get back here.")
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
