import SwiftUI

/// Macros ("good night = dark mode; turn off wifi") and nicknames
/// ("mama = +15551234567"), edited as rows and saved to Orbit's files.
struct ConfEditor: View {
    enum Kind {
        case macros, people

        var title: String { self == .macros ? "Macros" : "People" }
        var subtitle: String {
            self == .macros
                ? "One phrase, several commands. Say the phrase and Orbit runs each command in order."
                : "Who you mean when you say a name. Anyone not listed is looked up in Contacts."
        }
        var namePlaceholder: String { self == .macros ? "good night" : "mama" }
        var valuePlaceholder: String {
            self == .macros ? "dark mode; turn off wifi; set a timer for 5 minutes" : "+15551234567 or an email"
        }
        var nameHeader: String { self == .macros ? "When you say" : "Name" }
        var valueHeader: String { self == .macros ? "Orbit does" : "Number or email" }
        var emptyText: String {
            self == .macros ? "No macros yet. Add one below." : "No nicknames yet. Add one below."
        }
    }

    let kind: Kind
    @ObservedObject var store: OrbitStore

    @State private var rows: [Row] = []
    @State private var loaded = false

    private struct Row: Identifiable, Equatable {
        let id = UUID()
        var name: String
        var value: String
    }

    private var saved: [ConfEntry] { kind == .macros ? store.macros : store.contacts }
    private var dirty: Bool {
        rows.map { ConfEntry(name: $0.name, value: $0.value) }
            .filter { !$0.name.isEmpty || !$0.value.isEmpty } != saved
    }

    var body: some View {
        Page {
            PageHeader(title: kind.title, subtitle: kind.subtitle) {
                HStack(spacing: 8) {
                    if dirty {
                        Button("Revert") { load() }
                            .buttonStyle(OrbitButtonStyle())
                    }
                    Button("Save") { save() }
                        .buttonStyle(OrbitButtonStyle(kind: .primary))
                        .disabled(!dirty)
                }
            }

            Card(padding: 0) {
                VStack(spacing: 0) {
                    HStack(spacing: 14) {
                        SectionLabel(kind.nameHeader).frame(width: 200, alignment: .leading)
                        SectionLabel(kind.valueHeader)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    Hairline()

                    if rows.isEmpty {
                        Text(kind.emptyText)
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.dim)
                            .padding(20)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    ForEach($rows) { $row in
                        HStack(spacing: 14) {
                            TextField(kind.namePlaceholder, text: $row.name)
                                .orbitField()
                                .frame(width: 200)
                            TextField(kind.valuePlaceholder, text: $row.value)
                                .orbitField()
                            Button {
                                rows.removeAll { $0.id == row.id }
                            } label: {
                                Image(systemName: "minus.circle")
                                    .font(.system(size: 15))
                                    .foregroundStyle(Theme.faint)
                            }
                            .buttonStyle(.plain)
                            .help("Remove")
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                    }

                    Hairline()
                    Button {
                        rows.append(Row(name: "", value: ""))
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                            Text(kind == .macros ? "Add a macro" : "Add a person")
                        }
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.amber)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 13)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            if kind == .macros {
                Text("Each step is an ordinary Orbit command, separated by semicolons, so a macro can do anything you could say.")
                    .font(Theme.caption(11.5))
                    .foregroundStyle(Theme.faint)
            }
        }
        .onAppear { if !loaded { load() } }
        .onChange(of: saved) { _, _ in if !dirty { load() } }
    }

    private func load() {
        rows = saved.map { Row(name: $0.name, value: $0.value) }
        loaded = true
    }

    private func save() {
        let entries = rows.map { ConfEntry(name: $0.name, value: $0.value) }
        if kind == .macros { store.saveMacros(entries) } else { store.saveContacts(entries) }
        load()
    }
}
