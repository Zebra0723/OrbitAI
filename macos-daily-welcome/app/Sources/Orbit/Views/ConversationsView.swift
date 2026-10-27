import SwiftUI

/// Every conversation, newest first, as a log, with what Orbit did along the way.
struct ConversationsView: View {
    @ObservedObject var store: OrbitStore
    @AppStorage("showActivity") private var showActivity = true
    @State private var selectedID: Int?
    @State private var query = ""

    private var filtered: [Session] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return store.sessions }
        return store.sessions.filter { $0.turns.contains { $0.text.lowercased().contains(q) } }
    }

    private var selected: Session? {
        filtered.first { $0.id == selectedID } ?? filtered.first
    }

    var body: some View {
        HStack(spacing: 0) {
            index.frame(width: 300)
            VRule()
            if let selected {
                detail(selected).id(selected.id)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    MonoLabel("Empty")
                    Headline(text: "Nothing said yet.", size: 34, color: Theme.ink3)
                    Text("Say \u{201C}hey orbit\u{201D} or use Talk. Every conversation lands here.")
                        .font(Theme.body(13.5))
                        .foregroundStyle(Theme.ink3)
                }
                .padding(56)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    // MARK: - Index

    private var index: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                MonoLabel("\(Format.index(store.sessions.count)) conversations")
                HStack(spacing: 8) {
                    Text("/")
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.ink3)
                    TextField("Search", text: $query)
                        .textFieldStyle(.plain)
                        .font(Theme.body(13))
                }
                .padding(.horizontal, 11)
                .frame(height: 32)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Theme.rule, lineWidth: 1))
            }
            .padding(.horizontal, 24)
            .padding(.top, 56)
            .padding(.bottom, 18)

            Rule()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filtered) { session in
                        IndexRow(session: session, selected: session.id == selected?.id) {
                            selectedID = session.id
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: - Detail

    private func detail(_ session: Session) -> some View {
        // What Orbit did between the first word and a few minutes after the last.
        let actions = store.events.filter {
            $0.date >= session.start.addingTimeInterval(-60) && $0.date <= session.end.addingTimeInterval(5 * 60)
        }
        var items: [(date: Date, turn: Turn?, event: Event?)] = session.turns.map {
            (date: $0.date, turn: Optional($0), event: Event?.none)
        }
        if showActivity {
            items += actions.map { (date: $0.date, turn: Turn?.none, event: Optional($0)) }
        }
        let ordered = items.enumerated().sorted {
            $0.element.date == $1.element.date ? $0.offset < $1.offset : $0.element.date < $1.element.date
        }.map(\.element)

        return Page(maxWidth: 900) {
            PageTitle(kicker: "\(Format.day(session.start)) · \(Format.clock(session.start))–\(Format.clock(session.end))",
                      title: session.title) {
                Toggle(isOn: $showActivity) { MonoLabel("Actions") }
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(ordered.enumerated()), id: \.offset) { _, item in
                    if let turn = item.turn {
                        LogLine(turn: turn)
                    } else if let event = item.event {
                        ActionLine(event: event)
                    }
                }
            }
        }
    }
}

private struct IndexRow: View {
    let session: Session
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(Format.day(session.start).uppercased())  \(Format.clock(session.start))")
                        .font(Theme.mono(10.5))
                        .tracking(0.6)
                        .foregroundStyle(Theme.ink3)
                    Spacer()
                    Text(Format.index(session.turns.filter { $0.role == .user }.count))
                        .font(Theme.mono(10.5))
                        .foregroundStyle(Theme.ink3)
                }
                Text(session.title)
                    .font(Theme.body(13.5, weight: selected ? .medium : .regular))
                    .foregroundStyle(selected ? Theme.ink : Theme.ink2)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Theme.surface : (hovering ? Theme.surface.opacity(0.5) : Color.clear))
            .overlay(alignment: .leading) {
                Rectangle().fill(Theme.ink).frame(width: 2).opacity(selected ? 1 : 0)
            }
            .overlay(alignment: .bottom) { Rule() }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// 09:42   →   Messaged Mama: running late
private struct ActionLine: View {
    let event: Event

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(Format.clock(event.date))
                .font(Theme.mono(11))
                .foregroundStyle(Theme.ink3)
                .frame(width: 64, alignment: .leading)
            Text("→")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.ink3)
                .frame(width: 70, alignment: .leading)
            Text(event.summary)
                .font(Theme.mono(12))
                .foregroundStyle(Theme.ink2)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Rule() }
    }
}
