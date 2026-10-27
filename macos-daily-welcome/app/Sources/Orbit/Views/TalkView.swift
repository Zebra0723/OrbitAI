import AVFoundation
import SwiftUI

/// Type to Orbit the way you'd talk to it. Same brain as "Hey Orbit":
/// it goes through `orbit plan`, asks before anything it would ask about
/// out loud, and can say the answer in Orbit's voice.
struct TalkView: View {
    @ObservedObject var store: OrbitStore
    @AppStorage("speakReplies") private var speakReplies = true

    @State private var input = ""
    @State private var working = false
    @State private var reply: String?
    @State private var pendingToken: String?
    @State private var player: AVAudioPlayer?
    @FocusState private var focused: Bool

    private var recent: [Turn] { Array(store.turns.filter { !$0.text.hasPrefix("\u{0}") }.suffix(8)) }

    var body: some View {
        Page(maxWidth: 760) {
            VStack(spacing: 18) {
                OrbitMark(active: working)
                    .frame(width: 120, height: 120)
                    .padding(.top, 20)
                Text(working ? "Thinking" : "Talk to Orbit")
                    .font(Theme.display(30))
                    .contentTransition(.opacity)
                    .animation(.easeOut(duration: 0.2), value: working)
                Text("The same as saying \u{201C}\(store.listener.wake.isEmpty ? "hey orbit" : store.listener.wake)\u{201D}, typed. Orbit only speaks when you speak to it.")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.dim)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            inputBar

            if let reply {
                replyCard(reply)
                    .transition(.opacity.combined(with: .offset(y: 8)))
            }

            if !recent.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel("Recently")
                    Card(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(recent.reversed().enumerated()), id: \.element.id) { index, turn in
                                if index > 0 { Hairline() }
                                TurnRow(turn: turn)
                            }
                        }
                    }
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.88), value: reply)
        .onAppear { focused = true }
    }

    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField("Ask or tell Orbit anything", text: $input)
                .textFieldStyle(.plain)
                .font(.system(size: 17, design: .rounded))
                .focused($focused)
                .onSubmit(send)
                .disabled(working)
            Toggle(isOn: $speakReplies) {
                Text("Speak")
                    .font(Theme.caption(12))
                    .foregroundStyle(Theme.dim)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .help("Play Orbit's answer out loud")
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.sky)
                    .frame(width: 32, height: 32)
                    .background(input.trimmingCharacters(in: .whitespaces).isEmpty ? Theme.faint : Theme.amber,
                                in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(working || input.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.leading, 20)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(Theme.card, in: Capsule())
        .overlay(Capsule().strokeBorder(working ? Theme.amber.opacity(0.6) : Theme.hairline, lineWidth: 1))
    }

    private func replyCard(_ text: String) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel("Orbit")
                Text(text)
                    .font(.system(size: 16, design: .rounded))
                    .lineSpacing(4)
                    .textSelection(.enabled)
                if let token = pendingToken {
                    HStack(spacing: 10) {
                        Button("Do it") { confirm(token) }
                            .buttonStyle(OrbitButtonStyle(kind: .primary))
                        Button("Cancel") { cancel(token) }
                            .buttonStyle(OrbitButtonStyle())
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !working else { return }
        input = ""
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

struct TurnRow: View {
    let turn: Turn

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(turn.role == .user ? "You" : "Orbit")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(turn.role == .user ? Theme.dim : Theme.amber)
                .frame(width: 44, alignment: .leading)
            Text(turn.text)
                .font(Theme.body(13.5))
                .foregroundStyle(turn.role == .user ? Theme.starlight : Theme.starlight.opacity(0.85))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(Format.time(turn.date))
                .font(Theme.caption(11))
                .foregroundStyle(Theme.faint)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
    }
}
