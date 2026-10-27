import Charts
import SwiftUI

/// How much you talk to Orbit, when, and what it does for you.
struct StatsView: View {
    @ObservedObject var store: OrbitStore
    @State private var hoveredDay: Date?

    private struct DayCount: Identifiable {
        let date: Date
        let count: Int
        var id: Date { date }
    }

    private struct HourCount: Identifiable {
        let hour: Int
        let count: Int
        var id: Int { hour }
    }

    private var said: [Turn] { store.turns.filter { $0.role == .user && !$0.text.hasPrefix("\u{0}") } }

    private var days: [DayCount] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var counts: [Date: Int] = [:]
        for turn in said { counts[calendar.startOfDay(for: turn.date), default: 0] += 1 }
        return (0..<14).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return DayCount(date: day, count: counts[day] ?? 0)
        }
    }

    private var hours: [HourCount] {
        var counts = [Int](repeating: 0, count: 24)
        for turn in said { counts[Calendar.current.component(.hour, from: turn.date)] += 1 }
        return counts.enumerated().map { HourCount(hour: $0.offset, count: $0.element) }
    }

    private var actionKinds: [(kind: String, count: Int)] {
        var counts: [String: Int] = [:]
        for event in store.events { counts[event.kind, default: 0] += 1 }
        return counts.map { (kind: $0.key, count: $0.value) }.sorted { $0.count > $1.count }.prefix(8).map { $0 }
    }

    var body: some View {
        Page(maxWidth: 1000) {
            PageTitle(kicker: "All time", title: "Stats")

            HStack(spacing: 0) {
                Figure(label: "Conversations", value: store.sessions.count)
                VRule()
                Figure(label: "Things said", value: said.count)
                VRule()
                Figure(label: "Actions taken", value: store.events.count)
                VRule()
                Figure(label: "Remembered", value: store.facts.count)
            }
            .frame(height: 104)
            .overlay(alignment: .top) { Rule() }
            .overlay(alignment: .bottom) { Rule() }

            VStack(alignment: .leading, spacing: 18) {
                SectionHeader(index: "01", title: "Per day") {
                    Text(daySummary)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.ink2)
                }
                Chart(days) { day in
                    BarMark(x: .value("Day", day.date, unit: .day), y: .value("Times", day.count), width: .ratio(0.5))
                        .foregroundStyle(hoveredDay == nil || isHovered(day) ? Theme.ink : Theme.ink3.opacity(0.5))
                        .cornerRadius(2)
                }
                .chartXSelection(value: $hoveredDay)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                            .font(Theme.mono(10))
                            .foregroundStyle(Theme.ink3)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine().foregroundStyle(Theme.rule)
                        AxisValueLabel().font(Theme.mono(10)).foregroundStyle(Theme.ink3)
                    }
                }
                .frame(height: 200)
            }

            HStack(alignment: .top, spacing: 48) {
                VStack(alignment: .leading, spacing: 18) {
                    SectionHeader(index: "02", title: "Time of day")
                    Chart(hours) { hour in
                        BarMark(x: .value("Hour", hour.hour), y: .value("Times", hour.count), width: .ratio(0.55))
                            .foregroundStyle(Theme.ink)
                            .cornerRadius(1.5)
                    }
                    .chartXAxis {
                        AxisMarks(values: [0, 6, 12, 18]) { value in
                            AxisValueLabel {
                                if let hour = value.as(Int.self) { Text(String(format: "%02d:00", hour)) }
                            }
                            .font(Theme.mono(10))
                            .foregroundStyle(Theme.ink3)
                        }
                    }
                    .chartYAxis(.hidden)
                    .frame(height: 140)
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(index: "03", title: "What it does")
                    if actionKinds.isEmpty {
                        Text("Nothing yet.")
                            .font(Theme.body(13.5))
                            .foregroundStyle(Theme.ink3)
                            .padding(.top, 6)
                    } else {
                        let most = max(1, actionKinds.first?.count ?? 1)
                        ForEach(actionKinds, id: \.kind) { row in
                            HStack(spacing: 14) {
                                Text(Self.kindLabel(row.kind))
                                    .font(Theme.body(13))
                                    .foregroundStyle(Theme.ink)
                                    .frame(width: 130, alignment: .leading)
                                    .lineLimit(1)
                                GeometryReader { proxy in
                                    Rectangle()
                                        .fill(Theme.ink2)
                                        .frame(width: max(2, proxy.size.width * CGFloat(row.count) / CGFloat(most)), height: 2)
                                        .frame(maxHeight: .infinity, alignment: .center)
                                }
                                .frame(height: 14)
                                Text(Format.index(row.count))
                                    .font(Theme.mono(11))
                                    .foregroundStyle(Theme.ink2)
                                    .frame(width: 30, alignment: .trailing)
                            }
                            .frame(height: 26)
                        }
                    }
                }
                .frame(width: 360)
            }
        }
    }

    private func isHovered(_ day: DayCount) -> Bool {
        guard let hoveredDay else { return false }
        return Calendar.current.isDate(day.date, inSameDayAs: hoveredDay)
    }

    private var daySummary: String {
        if let day = days.first(where: isHovered) {
            return "\(day.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)).uppercased())  \(Format.index(day.count))"
        }
        return "\(Format.index(days.reduce(0) { $0 + $1.count })) IN 14 DAYS"
    }

    /// "add_reminder" → "Add reminder".
    private static func kindLabel(_ kind: String) -> String {
        let words = kind.replacingOccurrences(of: "_", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}

/// A label over a big, light numeral.
private struct Figure: View {
    let label: String
    let value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel(label)
            Text("\(value)")
                .font(Theme.numeral(46))
                .tracking(-1)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
