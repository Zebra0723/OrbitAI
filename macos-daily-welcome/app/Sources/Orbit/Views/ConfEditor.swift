import SwiftUI

/// Macros ("good night = dark mode; turn off wifi") and nicknames
/// ("mama = +15551234567"), edited as a table and saved to Orbit's files.
struct ConfEditor: View {
    enum Kind {
        case macros, people

        var title: String { self == .macros ? "Macros" : "People" }
        var subtitle: String {
            self == .macros
                ? "One phrase, several commands. Say the phrase and Orbit runs each command in order. Separate steps with semicolons."
                : "Who you mean when you say a name. Anyone not listed here is looked up in Contacts."
        }
        var namePlaceholder: String { self == .macros ? "good night" : "mama" }
        var valuePlaceholder: String {
            self == .macros ? "dark mode; turn off wifi; set a timer for 5 minutes" : "+15551234567"
        }
        var nameHeader: String { self == .macros ? "When you say" : "Name" }
        var valueHeader: String { self == .macros ? "Orbit does" : "Number or email" }
        var addTitle: String { self == .macros ? "Add macro" : "Add person" }
        var file: String { self == .macros ? "macros.conf" : "contacts.conf" }
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
            PageTitle(kicker: "~/.config/daily-welcome/\(kind.file)", title: kind.title, subtitle: kind.subtitle) {
                HStack(spacing: 8) {
                    if dirty {
                        Button("Revert") { load() }
                            .buttonStyle(InstrumentButtonStyle())
                    }
                    Button("Save") { save() }
                        .buttonStyle(InstrumentButtonStyle(kind: .primary))
                        .disabled(!dirty)
                        .opacity(dirty ? 1 : 0.35)
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 16) {
                    MonoLabel("#").frame(width: 32, alignment: .leading)
                    MonoLabel(kind.nameHeader).frame(width: 200, alignment: .leading)
                    MonoLabel(kind.valueHeader)
                    Spacer()
                }
                .padding(.bottom, 10)
                Rule(strong: true)

                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    HStack(spacing: 16) {
                        Text(Format.index(index + 1))
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.ink3)
                            .frame(width: 32, alignment: .leading)
                        TextField(kind.namePlaceholder, text: binding(row.id, \.name))
                            .textFieldStyle(.plain)
                            .font(Theme.body(13.5, weight: .medium))
                            .frame(width: 200)
                        TextField(kind.valuePlaceholder, text: binding(row.id, \.value))
                            .textFieldStyle(.plain)
                            .font(Theme.mono(12.5))
                            .foregroundStyle(Theme.ink2)
                        Button {
                            rows.removeAll { $0.id == row.id }
                        } label: {
                            Text("Remove")
                                .font(Theme.mono(10.5))
                                .foregroundStyle(Theme.ink3)
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(height: 44)
                    .overlay(alignment: .bottom) { Rule() }
                }

                Button {
                    rows.append(Row(name: "", value: ""))
                } label: {
                    HStack(spacing: 16) {
                        Text("+")
                            .font(Theme.mono(13))
                            .frame(width: 32, alignment: .leading)
                        Text(kind.addTitle.uppercased())
                            .font(Theme.mono(10.5, weight: .medium))
                            .tracking(1.2)
                        Spacer()
                    }
                    .foregroundStyle(Theme.ink2)
                    .frame(height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear { if !loaded { load() } }
        .onChange(of: saved) { _, _ in if !dirty { load() } }
    }

    /// A binding to one field of one row, found by id so removing rows can't misalign it.
    private func binding(_ id: UUID, _ field: WritableKeyPath<Row, String>) -> Binding<String> {
        Binding(
            get: { rows.first { $0.id == id }?[keyPath: field] ?? "" },
            set: { value in
                if let index = rows.firstIndex(where: { $0.id == id }) { rows[index][keyPath: field] = value }
            }
        )
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
