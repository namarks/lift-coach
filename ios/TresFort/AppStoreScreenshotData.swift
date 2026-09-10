#if DEBUG && targetEnvironment(simulator)
import Foundation

/// Fictional sample training for App Store asset capture. No account, provider,
/// training recommendation or production record is represented by these values.
enum AppStoreScreenshotData {
    private static let movements: [(id: String, name: String, muscle: String, weight: Int, reps: Int)] = [
        ("squat", "Barbell Squat", "legs", 135, 5),
        ("row", "Dumbbell Row", "back", 40, 10),
        ("press", "Dumbbell Bench Press", "chest", 35, 8),
    ]

    static var catalog: [[String: Any]] {
        movements.map { ["id": $0.id, "name": $0.name, "primary_muscle": $0.muscle,
                        "modality": $0.id == "squat" ? "barbell" : "dumbbell", "unit": "lb"] }
    }

    private static func slots(prefix: String) -> [[String: Any]] {
        movements.enumerated().map { index, movement in
            ["id": "\(prefix)-\(movement.id)", "exercise_id": movement.id,
             "exercise_name": movement.name, "exercise_unit": "lb",
             "exercise_modality": movement.id == "squat" ? "barbell" : "dumbbell",
             "order_index": index, "target_sets": 3, "target_reps": movement.reps,
             "rest_seconds": 90, "target_weight": movement.weight]
        }
    }

    static var plan: [String: Any] {
        ["id": "synthetic-plan", "name": "Weekly Strength", "version": 1,
         "meta": "{\"schedule\":{\"version\":1,\"week\":{\"tue\":\"synthetic-day\",\"thu\":\"strength-b\",\"sat\":\"synthetic-day\"}}}",
         "days": [["id": "synthetic-day", "name": "Strength A", "order_index": 0,
                   "exercises": slots(prefix: "a")],
                  ["id": "strength-b", "name": "Strength B", "order_index": 1,
                   "exercises": slots(prefix: "b")]]]
    }

    private static let dates = ["2026-08-29", "2026-09-01", "2026-09-03", "2026-09-05"]
    static var sessions: [[String: Any]] {
        dates.enumerated().map { index, date in
            ["id": "sample-session-\(index)", "date": date, "status": "completed",
             "workout_id": "synthetic-day", "attempt": 1, "updated_at": 1_788_000_000_000 + index,
             "notes": "Steady pace. Felt good today.", "perceived_fatigue": 5]
        }
    }

    static var sets: [[String: Any]] {
        var result: [[String: Any]] = []
        for dayIndex in dates.indices {
            for movement in movements {
                for setIndex in 1...3 {
                    let row: [String: Any] = ["id": "sample-\(dayIndex)-\(movement.id)-\(setIndex)",
                     "session_id": "sample-session-\(dayIndex)", "exercise_id": movement.id,
                     "template_exercise_id": "a-\(movement.id)", "set_index": setIndex,
                     "weight": movement.weight, "reps": movement.reps, "rpe": 7,
                     "is_warmup": 0, "is_timed": 0,
                     "logged_at": 1_788_000_000_000 + dayIndex * 100 + setIndex,
                     "updated_at": 1_788_000_000_000 + dayIndex * 100 + setIndex]
                    result.append(row)
                }
            }
        }
        return result
    }
}
#endif
