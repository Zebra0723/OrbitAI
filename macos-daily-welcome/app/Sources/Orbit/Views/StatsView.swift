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

    /// The things it did most, by kind ("message", "add_reminder"…).
    private var actionKinds: [(kind: String, count: Int)] {
        var counts: [String: Int] = [:]
        for event in store.events { counts[event.kind, default: 0] += 1 }
        return counts.map { (kind: $0.key, count: $0.value) }.sorted { $0.count > $1.count }.prefix(8).map { $0 }
    }

    var body: some View {
        Page(maxWidth: 980) {
            PageHeader(title: "Stats", subtitle: "Everything you've said to Orbit, and everything it's done.")

            HStack(spacing: 14) {
                Tile(label: "Conversations", value: "\(store.sessions.count)")
                Tile(label: "Things said", value: "\(said.count)")
                Tile(label: "Actions taken", value: "\(store.events.count)")
                Tile(label: "Remembered", value: "\(store.facts.count)")
            }

            Card {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Talked to per day").font(Theme.title())
                        Spacer()
                        Text(daySummary)
                            .font(Theme.caption(12))
                            .foregroundStyle(Theme.dim)
                            .monospacedDigit()
                    }
                    Chart(days) { day in
                        BarMark(x: .value("Day", day.date, unit: .day), y: .value("Times", day.count),
                                width: .ratio(0.6))
                            .foregroundStyle(Theme.amberData.opacity(hoveredDay == nil || isHovered(day) ? 1 : 0.4))
                            .cornerRadius(4)
                    }
                    .chartXSelection(value: $hoveredDay)
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                                .font(Theme.caption(10.5))
                                .foregroundStyle(Theme.faint)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                            AxisGridLine().foregroundStyle(Theme.hairline)
                            AxisValueLabel().font(Theme.caption(10.5)).foregroundStyle(Theme.faint)
                        }
                    }
                    .frame(height: 190)
                }
            }

            HStack(alignment: .top, spacing: 14) {
                Card {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Time of day").font(Theme.title())
                        Chart(hours) { hour in
                            BarMark(x: .value("Hour", hour.hour), y: .value("Times", hour.count), width: .ratio(0.7))
                                .foregroundStyle(Theme.amberData)
                                .cornerRadius(3)
                        }
                        .chartXAxis {
                            AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                                AxisValueLabel {
                                    if let hour = value.as(Int.self) { Text(Self.hourLabel(hour)) }
                                }
                                .font(Theme.caption(10.5))
                                .foregroundStyle(Theme.faint)
                            }
                        }
                        .chartYAxis(.hidden)
                        .frame(height: 140)
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("What it does").font(Theme.title())
                        if actionKinds.isEmpty {
                            Text("Nothing yet.")
                                .font(Theme.body(13))
                                .foregroundStyle(Theme.dim)
                        } else {
                            let most = max(1, actionKinds.first?.count ?? 1)
                            ForEach(actionKinds, id: \.kind) { row in
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text(Self.kindLabel(row.kind))
                                            .font(.system(size: 12.5, weight: .medium, design: .rounded))
                                        Spacer()
                                        Text("\(row.count)")
                                            .font(Theme.caption(12))
                                            .foregroundStyle(Theme.dim)
                                            .monospacedDigit()
                                    }
                                    GeometryReader { proxy in
                                        ZStack(alignment: .leading) {
                                            Capsule().fill(Theme.cardHigh)
                                            Capsule().fill(Theme.amberData)
                                                .frame(width: max(5, proxy.size.width * CGFloat(row.count) / CGFloat(most)))
                                        }
                                    }
                                    .frame(height: 5)
                                }
                            }
                        }
                    }
                }
                .frame(width: 340)
            }
        }
    }

    private func isHovered(_ day: DayCount) -> Bool {
        guard let hoveredDay else { return false }
        return Calendar.current.isDate(day.date, inSameDayAs: hoveredDay)
    }

    private var daySummary: String {
        if let day = days.first(where: isHovered) {
            return "\(day.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())): \(day.count)"
        }
        return "\(days.reduce(0) { $0 + $1.count }) in the last 14 days"
    }

    private static func hourLabel(_ hour: Int) -> String {
        switch hour {
        case 0: return "12am"
        case 12: return "12pm"
        case 1..<12: return "\(hour)am"
        default: return "\(hour - 12)pm"
        }
    }

    /// "add_reminder" → "Add reminder".
    private static func kindLabel(_ kind: String) -> String {
        let words = kind.replacingOccurrences(of: "_", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}

private struct Tile: View {
    let label: String
    let value: String

    var body: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(label)
                    .font(Theme.caption(11.5))
                    .foregroundStyle(Theme.dim)
                Text(value)
                    .font(Theme.number(28))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
    }
}
