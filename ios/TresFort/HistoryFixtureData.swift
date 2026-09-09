#if DEBUG && targetEnvironment(simulator)
import Foundation

/// Synthetic values only; excluded from release and physical-device builds.
enum HistoryFixtureData {
    static func progressDataset() -> StateResponse {
        let dates = ["2026-05-26", "2026-06-14", "2026-07-01"]
        let sessions = dates.enumerated().map { index, date in
            SessionRow(id: "session-\(index)", date: date, status: "completed", day_template_id: nil,
                updated_at: 1_000 + index, attempt: 1)
        }
        let sets = sessions.enumerated().map { index, session in
            SetLog(id: "set-\(index)", session_id: session.id, exercise_id: "exercise-0",
                template_exercise_id: nil, set_index: 1, weight: index == 1 ? 33 : 35,
                reps: index == 2 ? 10 : 8, rpe: nil, is_warmup: 0, logged_at: 1_000 + index,
                duration_s: nil, is_timed: 0, deleted_at: nil, updated_at: 1_000 + index)
        }
        return StateResponse(plan: nil, plan_version: 0, sessions: sessions, sets: sets,
            external_events: [], external_activities: [], activities: [], server_time: 200_000)
    }

    static func dataset(sessionCount: Int) -> StateResponse {
        let end = CalendarProjection.date(from: "2026-09-08")!
        let sessions = (0..<sessionCount).map { index in
            SessionRow(id: "session-\(index)",
                date: CalendarProjection.dateString(CalendarProjection.calendar.date(byAdding: .day,
                    value: -((sessionCount - index - 1) * 7 / 4), to: end)!),
                status: "completed", day_template_id: nil, updated_at: 1_000 + index, attempt: 1)
        }
        var sets: [SetLog] = []
        for (index, session) in sessions.enumerated() {
            for offset in 0..<24 {
                let exerciseID = "exercise-\((index * 6 + offset / 4) % 40)"
                let weight = Double(45 + offset / 4 * 10)
                sets.append(SetLog(id: "set-\(index)-\(offset)", session_id: session.id,
                    exercise_id: exerciseID, template_exercise_id: nil,
                    set_index: offset % 4 + 1, weight: weight, reps: 5,
                    rpe: nil, is_warmup: 0, logged_at: index * 100 + offset,
                    duration_s: nil, is_timed: 0, deleted_at: nil, updated_at: index * 100 + offset))
            }
        }
        return StateResponse(plan: nil, plan_version: 0, sessions: sessions, sets: sets,
            external_events: [], external_activities: [], activities: [], server_time: 200_000)
    }
}
#endif
