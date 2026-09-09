import SwiftUI

/// Schedule membership belongs to the plan, not to a workout's identity.
enum WorkoutLibraryPolicy {
    static func isScheduled(workoutID: String, plan: PlanTree?) -> Bool {
        PlanSchedule.weekdayKeys.contains { plan?.schedule?.templateID(forWeekdayKey: $0) == workoutID }
    }

    static func scheduleBadge(workoutID: String, plan: PlanTree?) -> String {
        let days = PlanSchedule.weekdayKeys.filter {
            plan?.schedule?.templateID(forWeekdayKey: $0) == workoutID
        }
        return days.isEmpty ? "On demand" : days.map { $0.capitalized }.joined(separator: " · ")
    }

    /// Use the persisted mapping. An unsaved picker draft must not accidentally
    /// schedule other workouts when the member chooses Unschedule on one card.
    static func unscheduling(workoutID: String, plan: PlanTree) -> [String: String] {
        Dictionary(uniqueKeysWithValues: PlanSchedule.weekdayKeys.map { key in
            let id = plan.schedule?.templateID(forWeekdayKey: key) ?? ""
            return (key, id == workoutID ? "" : id)
        })
    }
}

struct WorkoutDateSheet: View {
    @ObservedObject var sync: SyncModel
    let workout: Workout
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var saving = false

    init(sync: SyncModel, workout: Workout) {
        self.sync = sync
        self.workout = workout
        _date = State(initialValue: CalendarProjection.date(from: sync.todayString) ?? Date())
    }

    private var dateString: String { CalendarProjection.dateString(date) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $date,
                               in: (CalendarProjection.date(from: sync.todayString) ?? Date())...,
                               displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .accessibilityIdentifier("workoutAssignmentDate")
                } footer: {
                    Text("Use \(workout.name) on this date. Your weekly schedule stays the same.")
                }
                Section {
                    if let reason = sync.calendarAssignmentUnavailableReason(date: dateString) {
                        Text(reason).foregroundStyle(Theme.muted)
                    } else if let current = sync.sessionDisplayTemplate(forDateString: dateString) {
                        Text("Replaces \(current.name) for this date only.")
                            .foregroundStyle(Theme.muted)
                    }
                    Button(saving ? "Saving…" : "Use \(workout.name)") {
                        saving = true
                        Task {
                            await sync.setCalendarOverride(date: dateString, dayID: workout.id)
                            saving = false
                            if sync.loadError == nil { dismiss() }
                        }
                    }
                    .disabled(saving || sync.isRoutineMutationInFlight
                        || sync.workout(id: workout.id) == nil
                        || sync.calendarAssignmentUnavailableReason(date: dateString) != nil)
                    .accessibilityIdentifier("assignLibraryWorkout")
                    if let error = sync.loadError {
                        Text(error).foregroundStyle(Theme.danger)
                    }
                }
            }
            .navigationTitle("Use on a date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .environment(\.calendar, CalendarProjection.calendar)
        .environment(\.timeZone, CalendarProjection.calendar.timeZone)
        .preferredColorScheme(.dark)
    }
}
