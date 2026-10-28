import AppKit
import SwiftUI

/// The microphone, the voice, and Orbit's settings file, as controls.
struct SettingsView: View {
    @ObservedObject var store: OrbitStore
    @State private var values: [String: String] = [:]
    @State private var output = ""
    @State private var busy = false
    @State private var muteLength = ""
    @State private var muteError = false

    private struct Setting {
        enum Kind { case text, number, toggle, choice([String]) }
        let key: String
        let label: String
        let help: String
        let kind: Kind
    }

    private struct SettingGroup {
        let title: String
        let settings: [Setting]
        init(_ title: String, _ settings: [Setting]) { self.title = title; self.settings = settings }
    }

    private static let groups: [SettingGroup] = [
        SettingGroup("You", [
            Setting(key: "WELCOME_NAME", label: "Your name", help: "What Orbit calls you.", kind: .text),
            Setting(key: "WELCOME_HONORIFIC", label: "Honorific", help: "How Orbit addresses you. Empty for just your name.", kind: .text),
        ]),
        SettingGroup("Listening", [
            Setting(key: "ORBIT_WAKE_WORD", label: "Wake word", help: "Ordinary words are recognised far better than invented ones.", kind: .text),
            Setting(key: "ORBIT_WAKE_ALIASES", label: "Also counts as the wake word", help: "Separated by |. What the recogniser hears instead.", kind: .text),
            Setting(key: "ORBIT_GREETING", label: "Greeting", help: "The answer to the wake word on its own.", kind: .text),
            Setting(key: "ORBIT_SIGNOFF", label: "Sign-off", help: "What ends a conversation.", kind: .text),
            Setting(key: "ORBIT_CONVERSATION", label: "Conversation mode", help: "Keep listening after a reply until you say thanks.", kind: .toggle),
            Setting(key: "ORBIT_ONDEVICE", label: "On-device recognition", help: "Keeps audio on this Mac. Hears invented names badly.", kind: .toggle),
            Setting(key: "ORBIT_PAUSE_ON_CALL", label: "Pause while you're on a call", help: "Shuts the microphone whenever another app is recording.", kind: .toggle),
            Setting(key: "ORBIT_REQUIRE_UNLOCKED", label: "Only when unlocked", help: "Ignore commands while the screen is locked.", kind: .toggle),
        ]),
        SettingGroup("Voice", [
            Setting(key: "WELCOME_TTS", label: "Who speaks", help: "auto tries ElevenLabs, then piper, then the built-in voice.", kind: .choice(["auto", "elevenlabs", "openai", "piper", "say"])),
            Setting(key: "WELCOME_ELEVEN_VOICE_ID", label: "ElevenLabs voice ID", help: "An ID always works; a name only if it's in your account.", kind: .text),
            Setting(key: "WELCOME_ELEVEN_SPEED", label: "Speed", help: "1.0 is normal.", kind: .number),
            Setting(key: "WELCOME_ELEVEN_STABILITY", label: "Stability", help: "Lower is more expressive, higher is steadier.", kind: .number),
            Setting(key: "WELCOME_VOLUME", label: "Volume", help: "0 to 1.", kind: .number),
            Setting(key: "WELCOME_SPEAK_RATE", label: "Built-in voice rate", help: "Words per minute. 175 is normal.", kind: .number),
        ]),
        SettingGroup("Understanding", [
            Setting(key: "ORBIT_NLU", label: "How it understands you", help: "A model handles phrasings nobody anticipated. rules needs no key.", kind: .choice(["claude", "openai", "rules"])),
            Setting(key: "ORBIT_MATCH_TONE", label: "Match my tone", help: "Clipped questions get clipped answers.", kind: .toggle),
            Setting(key: "ORBIT_FREEFORM", label: "Freeform commands", help: "Claude writes a command for anything not in the catalogue.", kind: .toggle),
            Setting(key: "ORBIT_GALAXY", label: "Galaxy Link", help: "Share memory with Comet, Nova and Zenith, and hand them what Orbit can't do.", kind: .toggle),
            Setting(key: "ORBIT_CONFIRM_CALLS", label: "Confirm calls", help: "Say the name back before dialling.", kind: .toggle),
        ]),
    ]

    private static var allKeys: [String] { groups.flatMap { $0.settings.map(\.key) } }

    var body: some View {
        Page {
            PageTitle(kicker: "~/.config/daily-welcome/config.sh", title: "Settings",
                      subtitle: "The same file the terminal uses. Changes apply to Orbit's next turn.")

            microphone
            sound
            voiceTools

            ForEach(Array(Self.groups.enumerated()), id: \.element.title) { index, group in
                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader(index: Format.index(index + 4), title: group.title)
                        .padding(.bottom, 4)
                    ForEach(group.settings, id: \.key) { setting in
                        row(setting)
                    }
                }
            }

            Text("Orbit only speaks when someone speaks to it. No setting changes that.")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.ink3)
        }
        .task { values = await OrbitCLI.settingValues(Self.allKeys) }
    }

    // MARK: - Microphone

    private var microphone: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(index: "01", title: "Microphone")
                .padding(.bottom, 4)
            HStack(spacing: 18) {
                OrbitGlyph(live: store.listener.isLive)
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 5) {
                    StatusLine(status: store.listener)
                    Text(store.listener.appRunning
                         ? "The menu bar app listens for the wake word. Option-Space skips it."
                         : "Start the menu bar app so Orbit can hear you.")
                        .font(Theme.body(12.5))
                        .foregroundStyle(Theme.ink3)
                }
                Spacer()
                if store.listener.appRunning {
                    Button(store.listener.paused ? "Turn on" : "Turn off") {
                        Task { await store.setListening(store.listener.paused) }
                    }
                    .buttonStyle(InstrumentButtonStyle(kind: store.listener.paused ? .primary : .ghost))
                } else {
                    Button("Start it") { startMenuBarApp() }
                        .buttonStyle(InstrumentButtonStyle(kind: .primary))
                }
            }
            .padding(.vertical, 18)
            .overlay(alignment: .bottom) { Rule() }
        }
    }

    // MARK: - Sound

    private static let mutePresets: [(String, String)] = [
        ("30 min", "30m"), ("1 hour", "1h"), ("2 hours", "2h"), ("8 hours", "8h"), ("Until I unmute", ""),
    ]

    /// Muted means silent: no voice, no chime, no timers, whatever asks.
    private var sound: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(index: "02", title: "Sound")
                .padding(.bottom, 4)
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(store.mute.isMuted ? store.mute.description : "Not muted")
                            .font(Theme.body(14, weight: .medium))
                            .foregroundStyle(store.mute.isMuted ? Theme.signal : Theme.ink)
                        Text("While muted Orbit makes no sound at all. It still answers here, in text.")
                            .font(Theme.body(12.5))
                            .foregroundStyle(Theme.ink3)
                    }
                    Spacer()
                    if store.mute.isMuted {
                        Button("Unmute") { Task { await store.unmute() } }
                            .buttonStyle(InstrumentButtonStyle(kind: .primary))
                    }
                }
                HStack(spacing: 8) {
                    ForEach(Self.mutePresets, id: \.0) { preset in
                        Button(preset.0) { mute(preset.1) }
                            .buttonStyle(InstrumentButtonStyle())
                    }
                }
                HStack(spacing: 8) {
                    TextField("45m, 3h, until 7:30, until 7pm", text: $muteLength)
                        .instrumentField(mono: true)
                        .frame(maxWidth: 280)
                        .onSubmit { mute(muteLength) }
                    Button("Mute") { mute(muteLength) }
                        .buttonStyle(InstrumentButtonStyle(kind: .primary))
                        .disabled(muteLength.trimmingCharacters(in: .whitespaces).isEmpty)
                    if muteError {
                        MonoLabel("Couldn't read that length", color: Theme.signal)
                    }
                }
            }
            .padding(.vertical, 18)
            .overlay(alignment: .bottom) { Rule() }
        }
    }

    private func mute(_ length: String) {
        Task {
            let ok = await store.mute(for: length)
            muteError = !ok
            if ok { muteLength = "" }
        }
    }

    private var voiceTools: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(index: "03", title: "Diagnostics")
                .padding(.bottom, 4)
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Button("Test voice") { runTool(["--test-voice"]) }
                        .buttonStyle(InstrumentButtonStyle(kind: .primary))
                    Button("Stop talking") { Task { _ = await OrbitCLI.orbit(["hush"]) } }
                        .buttonStyle(InstrumentButtonStyle())
                    Button("Check install") { runTool(["--doctor"], timeout: 120) }
                        .buttonStyle(InstrumentButtonStyle())
                    if busy {
                        MonoLabel("Running…").padding(.leading, 8)
                    }
                }
                if !output.isEmpty {
                    ScrollView {
                        Text(output)
                            .font(Theme.mono(11.5))
                            .foregroundStyle(Theme.ink2)
                            .lineSpacing(3)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                    }
                    .frame(maxHeight: 240)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Theme.rule, lineWidth: 1))
                }
            }
            .padding(.vertical, 18)
            .overlay(alignment: .bottom) { Rule() }
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(_ setting: Setting) -> some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text(setting.label)
                    .font(Theme.body(13.5, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Text(setting.help)
                    .font(Theme.body(12.5))
                    .foregroundStyle(Theme.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 24)
            control(setting)
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Rule() }
    }

    @ViewBuilder
    private func control(_ setting: Setting) -> some View {
        switch setting.kind {
        case .toggle:
            Toggle("", isOn: Binding(
                get: { values[setting.key] == "1" },
                set: { save(setting.key, $0 ? "1" : "0") }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        case .choice(let options):
            let current = values[setting.key] ?? ""
            Picker("", selection: Binding(get: { current }, set: { save(setting.key, $0) })) {
                ForEach(options.contains(current) || current.isEmpty ? options : [current] + options, id: \.self) {
                    Text($0).tag($0)
                }
            }
            .labelsHidden()
            .frame(width: 180)
        case .text, .number:
            SettingField(value: values[setting.key] ?? "", numeric: { if case .number = setting.kind { return true }; return false }()) {
                save(setting.key, $0)
            }
        }
    }

    private func save(_ key: String, _ value: String) {
        values[key] = value
        OrbitCLI.writeSetting(key, value)
    }

    private func runTool(_ arguments: [String], timeout: TimeInterval = 60) {
        busy = true
        output = ""
        Task {
            let result = await OrbitCLI.welcome(arguments, timeout: timeout)
            output = result.output.isEmpty ? (result.ok ? "Done." : "It didn't work.") : result.output
            busy = false
        }
    }

    private func startMenuBarApp() {
        let app = OrbitPaths.home.appendingPathComponent("Applications/DailyWelcome.app")
        NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// A text field that saves when you press Return or leave it.
private struct SettingField: View {
    let value: String
    let numeric: Bool
    let onCommit: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text)
            .instrumentField(mono: numeric)
            .frame(width: numeric ? 90 : 240)
            .multilineTextAlignment(numeric ? .trailing : .leading)
            .focused($focused)
            .onAppear { text = value }
            .onChange(of: value) { _, new in if !focused { text = new } }
            .onSubmit { commit() }
            .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
    }

    private func commit() {
        guard text != value else { return }
        onCommit(text)
    }
}
