import SwiftUI

/// Every conversation, newest first, with what Orbit did along the way.
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
            list.frame(width: 320)
            Rectangle().fill(Theme.hairline).frame(width: 1)
            if let selected {
                detail(selected).id(selected.id)
            } else {
                VStack(spacing: 14) {
                    OrbitMark(active: false).frame(width: 56, height: 56).opacity(0.7)
                    Text("Nothing said yet")
                        .font(Theme.display(22))
                    Text("Say \u{201C}hey orbit\u{201D}, or use Talk. Every conversation shows up here.")
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.dim)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Conversations")
                    .font(Theme.display(24))
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.faint)
                    TextField("Search everything said", text: $query)
                        .textFieldStyle(.plain)
                        .font(Theme.body(13))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.card, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
            }
            .padding(.horizontal, 20)
            .padding(.top, 48)
            .padding(.bottom, 14)

            Hairline()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(filtered) { session in
                        SessionRow(session: session, selected: session.id == selected?.id) {
                            selectedID = session.id
                        }
                    }
                }
                .padding(10)
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.sidebar.opacity(0.5))
    }

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

        return Page(maxWidth: 820) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("\(Format.day(session.start)), \(Format.time(session.start))")
                    Text(session.title)
                        .font(Theme.display(26))
                        .textSelection(.enabled)
                }
                Spacer(minLength: 20)
                Toggle(isOn: $showActivity) {
                    Text("Show what Orbit did")
                        .font(Theme.caption(12))
                        .foregroundStyle(Theme.dim)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(ordered.enumerated()), id: \.offset) { _, item in
                    if let turn = item.turn {
                        Bubble(turn: turn)
                    } else if let event = item.event {
                        ActivityLine(event: event)
                    }
                }
            }
        }
    }
}

private struct SessionRow: View {
    let session: Session
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                Text(session.title)
                    .font(.system(size: 13.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.starlight)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text("\(Format.day(session.start)), \(Format.time(session.start))  ·  \(session.turns.filter { $0.role == .user }.count) said")
                    .font(Theme.caption(11))
                    .foregroundStyle(Theme.faint)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Theme.cardHigh : (hovering ? Theme.card : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// You on the right, Orbit on the left, like any conversation.
private struct Bubble: View {
    let turn: Turn

    var body: some View {
        let mine = turn.role == .user
        HStack {
            if mine { Spacer(minLength: 80) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 5) {
                Text(turn.text)
                    .font(.system(size: 14.5, design: .rounded))
                    .foregroundStyle(mine ? Theme.sky : Theme.starlight)
                    .textSelection(.enabled)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 10)
                    .background(mine ? Theme.amber : Theme.cardHigh,
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                Text(Format.time(turn.date))
                    .font(Theme.caption(10.5))
                    .foregroundStyle(Theme.faint)
                    .padding(.horizontal, 6)
            }
            if !mine { Spacer(minLength: 80) }
        }
    }
}

private struct ActivityLine: View {
    let event: Event

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .strokeBorder(Theme.ring, lineWidth: 1.5)
                .frame(width: 9, height: 9)
            Text(event.summary)
                .font(Theme.caption(12))
                .foregroundStyle(Theme.ring)
            Text(Format.time(event.date))
                .font(Theme.caption(10.5))
                .foregroundStyle(Theme.faint)
        }
        .frame(maxWidth: .infinity)
    }
}
