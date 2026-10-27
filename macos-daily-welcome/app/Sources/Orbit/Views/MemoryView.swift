import SwiftUI

/// The facts Orbit carries into every conversation.
struct MemoryView: View {
    @ObservedObject var store: OrbitStore
    @State private var draft = ""
    @State private var confirmingClear = false

    var body: some View {
        Page {
            PageHeader(title: "Memory",
                       subtitle: "What Orbit knows about you. It notes new things as you talk; you can add and remove them here.") {
                if !store.facts.isEmpty {
                    Button("Clear all") { confirmingClear = true }
                        .buttonStyle(OrbitButtonStyle(kind: .destructive))
                        .confirmationDialog("Forget everything Orbit knows about you?", isPresented: $confirmingClear) {
                            Button("Forget everything", role: .destructive) { store.clearFacts() }
                        } message: {
                            Text("Conversations stay; only the remembered facts are removed.")
                        }
                }
            }

            HStack(spacing: 10) {
                TextField("Something for Orbit to remember", text: $draft)
                    .orbitField()
                    .onSubmit(add)
                Button("Remember", action: add)
                    .buttonStyle(OrbitButtonStyle(kind: .primary))
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if store.facts.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Nothing remembered yet")
                            .font(Theme.title())
                        Text("Tell Orbit things like \u{201C}my sister is called Priya\u{201D} and it keeps them.")
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.dim)
                    }
                }
            } else {
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(store.facts.enumerated()), id: \.element.id) { index, fact in
                            if index > 0 { Hairline() }
                            FactRow(fact: fact) { store.deleteFact(fact) }
                        }
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
    let fact: Fact
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Circle().fill(Theme.amber).frame(width: 5, height: 5)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            VStack(alignment: .leading, spacing: 4) {
                Text(fact.text)
                    .font(Theme.body(14))
                    .textSelection(.enabled)
                if !fact.date.isEmpty {
                    Text("Noted \(fact.date)")
                        .font(Theme.caption(11))
                        .foregroundStyle(Theme.faint)
                }
            }
            Spacer()
            Button("Forget", action: onDelete)
                .buttonStyle(OrbitButtonStyle(kind: .destructive))
                .opacity(hovering ? 1 : 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
