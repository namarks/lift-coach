import XCTest
@testable import TresFort

final class ExerciseHistoryProgressTests: XCTestCase {
    private func history(_ samples: [(date: String, weight: Double, value: Int, timed: Bool)],
                         modality: String = "machine") -> [TrainingHistoryIndex.SessionStat] {
        let catalog = [ExerciseCatalog(id: "exercise", name: "Exercise", primary_muscle: "core",
            modality: modality, unit: "lb", laterality: nil, load_mode: nil, demo_slug: nil)]
        let sessions = samples.enumerated().map { index, sample in
            SessionRow(id: "session-\(index)", date: sample.date, status: "completed", day_template_id: nil)
        }
        let sets = samples.enumerated().map { index, sample in
            SetLog(id: "set-\(index)", session_id: sessions[index].id, exercise_id: "exercise",
                template_exercise_id: nil, set_index: 1, weight: sample.weight, reps: sample.value,
                rpe: nil, is_warmup: 0, logged_at: index,
                duration_s: sample.timed ? sample.value : nil, is_timed: sample.timed ? 1 : 0,
                deleted_at: nil)
        }
        return TrainingHistoryIndex(sessions: sessions, sets: sets, catalog: catalog).history(for: "exercise")
    }

    func testChangingWeightDefaultsToOneOverallTrendWithSparseComparisons() throws {
        let options = ExerciseHistoryProgress.options(history([
            ("2026-05-26", 35, 8, false), ("2026-06-14", 33, 8, false)
        ]))
        let selected = try XCTUnwrap(ExerciseHistoryProgress.selected(nil, from: options))
        XCTAssertEqual(selected.id, .estimatedOneRepMax)
        XCTAssertTrue(selected.hasTrend)
        XCTAssertEqual(selected.points.map(\.value), [44.3, 41.8])
        XCTAssertEqual(options.dropFirst().map(\.hasTrend), [false, false])
        XCTAssertEqual(options.dropFirst().map { $0.points[0].value }, [8, 8])
    }

    func testRepeatedWeightBecomesTrendAndOtherWeightRemainsSummary() throws {
        let options = ExerciseHistoryProgress.options(history([
            ("2026-05-26", 35, 8, false), ("2026-06-14", 33, 8, false),
            ("2026-07-01", 35, 10, false)
        ]))
        let repeated = try XCTUnwrap(options.first { $0.title == "35 lb · Best reps" })
        XCTAssertTrue(repeated.hasTrend)
        XCTAssertEqual(repeated.points.map(\.value), [8, 10])
        XCTAssertFalse(try XCTUnwrap(options.first { $0.title == "33 lb · Best reps" }).hasTrend)
    }

    func testMultipleSessionsOnOneDayAreOneBestValueWithoutTrend() {
        let options = ExerciseHistoryProgress.options(history([
            ("2026-06-14", 33, 8, false), ("2026-06-14", 33, 10, false)
        ]))
        XCTAssertTrue(options.allSatisfy { !$0.hasTrend })
        XCTAssertEqual(options.last?.points.map(\.value), [10])
    }

    func testBodyweightAssistanceAndHoldsStaySeparateWithoutEstimate() throws {
        let options = ExerciseHistoryProgress.options(history([
            ("2026-05-26", 0, 8, false), ("2026-06-14", 0, 10, false),
            ("2026-07-01", -30, 15, false), ("2026-07-02", 0, 45, true)
        ], modality: "bw"))
        XCTAssertEqual(options.count, 3)
        XCTAssertFalse(options.contains { $0.id == .estimatedOneRepMax })
        XCTAssertEqual(ExerciseHistoryProgress.selected(nil, from: options)?.title, "Strict BW · Best hold")
        let strict = try XCTUnwrap(options.first { $0.title == "Strict BW · Best reps" })
        XCTAssertEqual(strict.points.map(\.value), [8, 10])
        XCTAssertTrue(strict.hasTrend)
        let assisted = try XCTUnwrap(options.first { $0.title == "BW−30 lb assist · Best reps" })
        XCTAssertEqual(assisted.points.map(\.value), [15])
        XCTAssertFalse(assisted.hasTrend)
    }

    func testSelectionSurvivesRefreshAndFallsBackIfConditionWasRemoved() throws {
        let options = ExerciseHistoryProgress.options(history([
            ("2026-05-26", 35, 8, false), ("2026-06-14", 33, 8, false)
        ]))
        let comparison = try XCTUnwrap(options.last)
        XCTAssertEqual(ExerciseHistoryProgress.selected(comparison.id, from: options)?.id, comparison.id)
        XCTAssertEqual(ExerciseHistoryProgress.selected(comparison.id, from: [options[0]])?.id,
                       .estimatedOneRepMax)
        XCTAssertNil(ExerciseHistoryProgress.selected(comparison.id, from: []))
    }
}
