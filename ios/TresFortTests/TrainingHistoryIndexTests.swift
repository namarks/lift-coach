#if targetEnvironment(simulator)
import XCTest
@testable import TresFort

@MainActor
final class TrainingHistoryIndexTests: XCTestCase {
    private final class Tokens: AppTokenStore {
        func load() -> String? { nil }
        func save(_ token: String) {}
        func clear() {}
    }

    func testPublishedMutationsInvalidateHistoryWithoutChangingDatePrecedence() throws {
        let suite = "TrainingHistoryIndexTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let auth = AuthModel(tokenStore: Tokens(), defaults: defaults)
        let model = SyncModel(auth: auth, defaults: defaults)
        let dataset = HistoryPerformanceTests.dataset(sessionCount: 12)
        model.sessions = dataset.sessions
        model.sets = dataset.sets
        let row = dataset.sets[0]
        let exercise = row.exercise_id
        XCTAssertEqual(model.latestHistory(for: exercise)?.id, model.history(for: exercise).last?.id)
        let oldCount = model.history(for: exercise).reduce(0) { $0 + $1.setCount }
        model.sets.removeAll { $0.id == row.id }
        XCTAssertEqual(model.history(for: exercise).reduce(0) { $0 + $1.setCount }, oldCount - 1)
        let date = dataset.sessions[0].date
        model.sessions.append(SessionRow(id: "skipped", date: date, status: "skipped", day_template_id: nil))
        XCTAssertEqual(model.sessionsByDate[date]?.id, dataset.sessions[0].id)
        model.sessions.removeAll { $0.id == dataset.sessions[0].id }
        XCTAssertEqual(model.sessionsByDate[date]?.id, "skipped")
        XCTAssertEqual(model.loggedSetCount(forDate: date), 0)
        model.catalog = [ExerciseCatalog(id: exercise, name: "Changed", primary_muscle: "legs",
            modality: "timed", unit: "sec", laterality: "unilateral", load_mode: "per_hand", demo_slug: nil)]
        XCTAssertEqual(model.exerciseName(exercise), "Changed")
        XCTAssertEqual(model.sides(for: exercise), 2)
        // Explicit per-set rep flags must continue winning over the new catalog.
        XCTAssertFalse(try XCTUnwrap(model.latestHistory(for: exercise)).hasTimedSets)
        model.sets.removeAll()
        XCTAssertTrue(model.loggedExerciseIDs.isEmpty)
        XCTAssertNil(model.latestHistory(for: exercise))
        XCTAssertTrue(model.history(for: exercise).isEmpty)
    }
}
#endif
