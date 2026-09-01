// Reminders and Calendar, read through EventKit instead of AppleScript.
//
// AppleScript was the wrong tool for both. Reminders' `whose` filters lie
// about due dates - a reminder with no due date still comes back from a
// query that excludes them, and comparing it to a date fails with -1700 -
// and Calendar refuses to answer at all unless the app happens to be
// running (-600). EventKit has neither problem, needs nothing launched,
// and asks for the ordinary Reminders and Calendars permissions rather
// than an Automation grant.
//
// Run as `DailyWelcome --dump-reminders` / `--dump-events`, printing the
// same tab-separated records the shell already speaks:
//     when <TAB> title <TAB> context
// Exit 0 with records, 3 if access was refused, 4 if it timed out.

import Foundation
import EventKit

enum DumpExit: Int32 {
    case ok = 0
    case denied = 3
    case timedOut = 4
}

private func fail(_ message: String, _ code: DumpExit) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code.rawValue)
}

private func timeString(_ date: Date) -> String {
    let f = DateFormatter()
    f.dateStyle = .none
    f.timeStyle = .short
    return f.string(from: date)
}

/// EventKit's callbacks are asynchronous and this is a one-shot command,
/// so each wait is bounded rather than trusting them to come back.
private func waitFor(_ seconds: TimeInterval, _ body: (@escaping () -> Void) -> Void) -> Bool {
    let semaphore = DispatchSemaphore(value: 0)
    body { semaphore.signal() }
    return semaphore.wait(timeout: .now() + seconds) == .success
}

private func grantAccess(to entity: EKEntityType, store: EKEventStore) -> Bool {
    var granted = false
    let answered = waitFor(20) { done in
        if #available(macOS 14.0, *) {
            switch entity {
            case .reminder: store.requestFullAccessToReminders { ok, _ in granted = ok; done() }
            case .event:    store.requestFullAccessToEvents { ok, _ in granted = ok; done() }
            @unknown default: granted = false; done()
            }
        } else {
            store.requestAccess(to: entity) { ok, _ in granted = ok; done() }
        }
    }
    guard answered else {
        fail("Timed out waiting for a permission answer.", .timedOut)
    }
    return granted
}

func dumpReminders() -> Never {
    let store = EKEventStore()
    guard grantAccess(to: .reminder, store: store) else {
        fail("No access to Reminders. System Settings > Privacy & Security > Reminders > DailyWelcome.", .denied)
    }

    let calendar = Calendar.current
    let dayStart = calendar.startOfDay(for: Date())
    guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
        fail("Couldn't work out the end of today.", .timedOut)
    }

    var found: [EKReminder] = []
    let answered = waitFor(25) { done in
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: dayEnd, calendars: nil)
        store.fetchReminders(matching: predicate) { reminders in
            found = reminders ?? []
            done()
        }
    }
    guard answered else { fail("Reminders took too long to answer.", .timedOut) }

    var lines: [String] = []
    for reminder in found {
        let title = (reminder.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { continue }

        // A reminder with no due date is only interesting if it's flagged;
        // undated lists are usually long and not about today.
        guard let components = reminder.dueDateComponents,
              let due = calendar.date(from: components) else {
            if reminder.priority > 0 && reminder.priority <= 4 {
                lines.append("flagged\t\(title)\t\(reminder.calendar?.title ?? "")")
            }
            continue
        }

        let when = due < dayStart ? "OVERDUE" : timeString(due)
        lines.append("\(when)\t\(title)\t\(reminder.calendar?.title ?? "")")
    }

    print(lines.joined(separator: "\n"))
    exit(DumpExit.ok.rawValue)
}

func dumpEvents() -> Never {
    let store = EKEventStore()
    guard grantAccess(to: .event, store: store) else {
        fail("No access to Calendar. System Settings > Privacy & Security > Calendars > DailyWelcome.", .denied)
    }

    let calendar = Calendar.current
    let dayStart = calendar.startOfDay(for: Date())
    guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
        fail("Couldn't work out the end of today.", .timedOut)
    }

    let predicate = store.predicateForEvents(withStart: dayStart, end: dayEnd, calendars: nil)
    let events = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }

    var lines: [String] = []
    for event in events {
        let title = (event.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { continue }
        // All-day events have no useful time to read out.
        let when = event.isAllDay ? "" : timeString(event.startDate)
        lines.append("\(when)\t\(title)\t\(event.calendar?.title ?? "")")
    }

    print(lines.joined(separator: "\n"))
    exit(DumpExit.ok.rawValue)
}
