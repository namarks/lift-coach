#if targetEnvironment(simulator)
import Foundation
import XCTest
@testable import TresFort

private final class PerformanceTokenStore: AppTokenStore {
    func load() -> String? { nil }
    func save(_ token: String) {}
    func clear() {}
}

/// Synthetic main-actor probes. Print raw samples so shared CI host timings
/// remain observations, not a flaky pass/fail performance threshold.
@MainActor
final class HistoryPerformanceTests: XCTestCase {
    private func sample(_ name: String, count: Int = 5, _ work: () throws -> Void) rethrows -> [Double] {
        var samples: [Double] = []
        for _ in 0..<count {
            let start = CFAbsoluteTimeGetCurrent()
            try work()
            samples.append((CFAbsoluteTimeGetCurrent() - start) * 1_000)
        }
        return samples
    }

    func testSmallAndFiveYearHistoryBaselines() throws {
        for sessionCount in [12, 1_040] {
            let suite = "HistoryPerformanceTests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let state = Self.dataset(sessionCount: sessionCount)
            let catalog = try JSONDecoder().decode([ExerciseCatalog].self, from:
                JSONSerialization.data(withJSONObject: (0..<40).map {
                    ["id": "exercise-\($0)", "name": "Exercise \($0)", "modality": "barbell", "unit": "lb", "primary_muscle": "legs"]
                }))
            StateSnapshotStore.save(state, userID: "synthetic-perf", defaults: defaults)
            ExerciseCatalogSnapshotStore.save(catalog, userID: "synthetic-perf", defaults: defaults)
            _ = StateSyncAccountStore.activate(userID: "synthetic-perf", defaults: defaults)
            let auth = AuthModel(tokenStore: PerformanceTokenStore(), defaults: defaults)
            auth.userID = "synthetic-perf"
            let model = SyncModel(auth: auth, defaults: defaults,
                now: { CalendarProjection.date(from: "2026-09-08")! },
                restActivityUpdater: { _, _ in }, restActivityEnder: {}, restNotificationCanceller: {})
            var timings: [String: [Double]] = [:]
            timings["cached_model_init"] = sample("launch") {
                // New defaults object prevents any process-local store cache
                // from disguising disk-envelope decoding in this cold probe.
                let cold = SyncModel(auth: auth, defaults: UserDefaults(suiteName: suite)!,
                    restActivityUpdater: { _, _ in }, restActivityEnder: {}, restNotificationCanceller: {})
                XCTAssertEqual(cold.sets.count, state.sets.count)
            }
            timings["calendar_open_and_feed_dates"] = sample("calendar") {
                for day in 1...30 {
                    _ = model.projection(for: String(format: "2026-09-%02d", day), today: "2026-09-08")
                }
                let activeDates = model.sessionsByDate.keys.filter { model.loggedSetCount(forDate: $0) > 0 }
                XCTAssertEqual(activeDates.count, sessionCount)
            }
            timings["calendar_scroll_20_rows"] = sample("scroll") {
                for row in state.sessions.suffix(20) {
                    XCTAssertEqual(model.setsForSession(row.id).count, 24)
                    _ = model.projection(for: row.date, today: "2026-09-08")
                }
            }
            timings["exercise_list_all_summaries"] = sample("history") {
                let ids = model.loggedExerciseIDs
                for id in ids { XCTAssertNotNil(model.latestHistory(for: id)) }
            }
            timings["exercise_detail"] = sample("detail") { XCTAssertFalse(model.history(for: "exercise-0").isEmpty) }
            timings["durable_log_enqueue_and_retire"] = sample("outbox") {
                let body = SetRequestBody(id: "synthetic-intent", exercise_id: "exercise-0", template_exercise_id: "slot-0",
                    set_index: 1, weight: 45, reps: 5, is_warmup: false, logged_at: 200_001,
                    duration_s: nil, is_timed: false, expected_attempt: 1)
                SetOutboxStore.enqueue(PendingSetIntent(body: body, date: "2026-09-08", workoutID: nil,
                    resolvedSessionID: state.sessions.last!.id, deliveryState: .queued, failedHTTPStatus: nil,
                    expectedAttempt: 1), userID: "synthetic-perf", defaults: defaults)
                XCTAssertEqual(SetOutboxStore.load(userID: "synthetic-perf", defaults: defaults).count, 1)
                SetOutboxStore.remove(ids: [body.id], userID: "synthetic-perf", defaults: defaults)
            }
            timings["snapshot_reservation"] = sample("reserve") {
                XCTAssertNotNil(StateSnapshotStore.reserveStateRequest(userID: "synthetic-perf", defaults: defaults))
            }
            timings["snapshot_ack_commit"] = sample("ack") {
                XCTAssertNotNil(StateSnapshotStore.mergeAcknowledgement(userID: "synthetic-perf", fallback: state, defaults: defaults) { current in
                    var sets = current.sets
                    sets[sets.count - 1] = state.sets.last!
                    return StateResponse(plan: current.plan, plan_version: current.plan_version,
                        sessions: current.sessions, sets: sets, external_events: current.external_events,
                        external_activities: current.external_activities, activities: current.activities,
                        server_time: current.server_time)
                })
            }
            let result: [String: Any] = ["sessions": sessionCount, "sets": state.sets.count,
                "exercises": 40, "years": sessionCount == 12 ? 0.06 : 5,
                "snapshot_bytes": defaults.data(forKey: StateSnapshotStore.scopedKey(userID: "synthetic-perf"))!.count,
                "runtime": ProcessInfo.processInfo.operatingSystemVersionString,
                "samples_ms": timings]
            let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
            print("HISTORY_PERF " + String(decoding: data, as: UTF8.self))
        }
    }

    static func dataset(sessionCount: Int) -> StateResponse {
        HistoryFixtureData.dataset(sessionCount: sessionCount)
    }
}
#endif
