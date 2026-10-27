import SwiftUI

/// The facts Orbit carries into every conversation.
struct MemoryView: View {
    @ObservedObject var store: OrbitStore
    @State private var draft = ""
    @State private var confirmingClear = false

    var body: some View {
        Page {
            PageTitle(kicker: "\(Format.index(store.facts.count)) facts", title: "Memory",
                      subtitle: "What Orbit knows about you. It notes new things as you talk; add or remove them here.") {
                if !store.facts.isEmpty {
                    Button("Clear all") { confirmingClear = true }
                        .buttonStyle(InstrumentButtonStyle(kind: .destructive))
                        .confirmationDialog("Forget everything Orbit knows about you?", isPresented: $confirmingClear) {
                            Button("Forget everything", role: .destructive) { store.clearFacts() }
                        } message: {
                            Text("Conversations stay; only the remembered facts are removed.")
                        }
                }
            }

            HStack(spacing: 10) {
                TextField("Something Orbit should remember", text: $draft)
                    .instrumentField()
                    .onSubmit(add)
                Button("Remember", action: add)
                    .buttonStyle(InstrumentButtonStyle(kind: .primary))
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(index: "01", title: "Known")
                    .padding(.bottom, 6)
                if store.facts.isEmpty {
                    Text("Nothing yet. Tell Orbit \u{201C}my sister is called Priya\u{201D} and it keeps it.")
                        .font(Theme.body(13.5))
                        .foregroundStyle(Theme.ink3)
                        .padding(.vertical, 14)
                } else {
                    ForEach(Array(store.facts.enumerated()), id: \.element.id) { index, fact in
                        FactRow(number: index + 1, fact: fact) { store.deleteFact(fact) }
                    }
                }
            }
        }
    }

    private func add() {
        let text = draft
        draft = ""
        Task { await store.addFact(text) }
    }
}

private struct FactRow: View {
    let number: Int
    let fact: Fact
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(Format.index(number))
                .font(Theme.mono(11))
                .foregroundStyle(Theme.ink3)
                .frame(width: 48, alignment: .leading)
            Text(fact.text)
                .font(Theme.body(14))
                .foregroundStyle(Theme.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if hovering {
                Button("Forget", action: onDelete)
                    .buttonStyle(InstrumentButtonStyle(kind: .destructive))
            } else {
                Text(fact.date)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.ink3)
            }
        }
        .frame(minHeight: 30)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rule() }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
