import AVFoundation
import SwiftUI

/// Type to Orbit the way you'd talk to it. Same brain as "Hey Orbit": it goes
/// through `orbit plan`, asks before anything it would ask about out loud, and
/// can say the answer in Orbit's voice.
struct TalkView: View {
    @ObservedObject var store: OrbitStore
    @AppStorage("speakReplies") private var speakReplies = true

    @State private var input = ""
    @State private var asked = ""
    @State private var working = false
    @State private var reply: String?
    @State private var pendingToken: String?
    @State private var player: AVAudioPlayer?
    @FocusState private var focused: Bool

    private var recent: [Turn] { Array(store.turns.filter { !$0.text.hasPrefix("\u{0}") }.suffix(10)) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 56) {
                    stage
                    if !recent.isEmpty { log }
                }
                .padding(.horizontal, 56)
                .padding(.top, 56)
                .padding(.bottom, 32)
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)

            Rule()
            commandLine
        }
        .onAppear { focused = true }
    }

    // MARK: - The stage: what you asked, and the answer, large

    private var stage: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 12) {
                Tally(live: working)
                MonoLabel(working ? "Working" : (reply == nil ? "Ready" : "Orbit"),
                          color: working ? Theme.ink : Theme.ink3)
            }

            if let reply {
                if !asked.isEmpty {
                    Text(asked)
                        .font(Theme.mono(12.5))
                        .foregroundStyle(Theme.ink3)
                }
                Text(reply)
                    .font(Theme.display(30, weight: .regular))
                    .tracking(Theme.tracking(for: 30))
                    .lineSpacing(6)
                    .foregroundStyle(Theme.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: 680, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let token = pendingToken {
                    HStack(spacing: 10) {
                        Button("Do it") { confirm(token) }
                            .buttonStyle(InstrumentButtonStyle(kind: .primary))
                        Button("Cancel") { cancel(token) }
                            .buttonStyle(InstrumentButtonStyle())
                    }
                    .padding(.top, 6)
                }
            } else if working {
                Headline(text: asked, size: 30, color: Theme.ink2)
                    .frame(maxWidth: 680, alignment: .leading)
            } else {
                Headline(text: "Say something.", size: 44, color: Theme.ink3)
                Text("Typing here is the same as saying \u{201C}\(store.listener.wake.isEmpty ? "hey orbit" : store.listener.wake)\u{201D}. Orbit only speaks when someone speaks to it.")
                    .font(Theme.body(13.5))
                    .foregroundStyle(Theme.ink3)
                    .frame(maxWidth: 520, alignment: .leading)
            }
        }
        .animation(.easeOut(duration: 0.2), value: reply)
        .animation(.easeOut(duration: 0.2), value: working)
    }

    // MARK: - Recent, as a log

    private var log: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(index: "Log", title: "Recently")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(recent.reversed()) { turn in
                    LogLine(turn: turn)
                }
            }
        }
    }

    // MARK: - The command line

    private var commandLine: some View {
        HStack(spacing: 16) {
            Text("›")
                .font(Theme.mono(18))
                .foregroundStyle(working ? Theme.signal : Theme.ink3)
            TextField("Ask or tell Orbit anything", text: $input)
                .textFieldStyle(.plain)
                .font(Theme.body(16))
                .foregroundStyle(Theme.ink)
                .focused($focused)
                .onSubmit(send)
                .disabled(working)
            Toggle(isOn: $speakReplies) { MonoLabel("Voice") }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .help("Play Orbit's answer out loud")
            Text("↵")
                .font(Theme.mono(12))
                .foregroundStyle(Theme.ink3)
                .frame(width: 26, height: 22)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.ruleStrong, lineWidth: 1))
                .opacity(input.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
        }
        .padding(.horizontal, 56)
        .frame(height: 68)
        .background(Theme.surface)
    }

    // MARK: - Actions

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !working else { return }
        input = ""
        asked = text
        working = true
        reply = nil
        pendingToken = nil
        Task {
            let (plan, raw) = await OrbitCLI.plan(text)
            handle(plan, raw: raw)
        }
    }

    private func confirm(_ token: String) {
        working = true
        pendingToken = nil
        reply = nil
        Task {
            let (plan, raw) = await OrbitCLI.confirm(token)
            handle(plan, raw: raw)
        }
    }

    private func cancel(_ token: String) {
        pendingToken = nil
        reply = "Cancelled."
        Task { await OrbitCLI.cancel(token) }
    }

    private func handle(_ plan: OrbitCLI.Plan?, raw: String) {
        working = false
        guard let plan else {
            reply = raw.isEmpty ? "Orbit didn't answer. Is it installed?" : raw
            return
        }
        reply = plan.speak.isEmpty ? "Done." : plan.speak
        pendingToken = plan.confirm && !plan.token.isEmpty ? plan.token : nil
        if speakReplies, !plan.audio.isEmpty {
            player = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: plan.audio))
            player?.play()
        }
        store.reload(force: false)
        focused = true
    }
}

/// 09:41   YOU     what's on my calendar
/// 09:41   ORBIT   Two events today…
struct LogLine: View {
    let turn: Turn

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(Format.clock(turn.date))
                .font(Theme.mono(11))
                .foregroundStyle(Theme.ink3)
                .frame(width: 64, alignment: .leading)
            Text(turn.role == .user ? "YOU" : "ORBIT")
                .font(Theme.mono(10.5, weight: .medium))
                .tracking(1)
                .foregroundStyle(turn.role == .user ? Theme.ink3 : Theme.ink2)
                .frame(width: 70, alignment: .leading)
            Text(turn.text)
                .font(Theme.body(13.5))
                .foregroundStyle(turn.role == .user ? Theme.ink2 : Theme.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Rule() }
    }
}
