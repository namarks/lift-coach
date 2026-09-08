import XCTest
@testable import TresFort

final class BodyweightMetricsTests: XCTestCase {
    private struct LegacyTopSet: Decodable {
        let est_1rm: Double
    }

    func testSetValueFormatterCoversAddedAssistedStrictAndTimedWork() {
        XCTAssertEqual(
            SetValueFormatter.value(
                weight: 45, reps: 5, durationSeconds: nil,
                timed: false, bodyweight: true),
            "BW+45 × 5")
        XCTAssertEqual(
            SetValueFormatter.value(
                weight: -30, reps: 8, durationSeconds: nil,
                timed: false, bodyweight: true),
            "BW−30 × 8")
        XCTAssertEqual(
            SetValueFormatter.value(
                weight: 0, reps: 8, durationSeconds: nil,
                timed: false, bodyweight: true),
            "BW × 8")
        XCTAssertEqual(
            SetValueFormatter.value(
                weight: -20, reps: 45, durationSeconds: 45,
                timed: true, bodyweight: false),
            "45s · 20 lb assist")
        XCTAssertEqual(
            SetValueFormatter.value(
                weight: 0, reps: 60, durationSeconds: nil,
                timed: true, bodyweight: false),
            "60s")
    }

    func testFeedTopSetDecodesMetricContextAndUsesSharedFormatter() throws {
        let data = Data(
            """
            {
              "exercise": "Pull-Up",
              "weight": -30,
              "reps": 12,
              "unit": "lb",
              "modality": "bw",
              "duration_s": null,
              "is_timed": false,
              "est_1rm": 0
            }
            """.utf8)
        let top = try JSONDecoder().decode(FeedSessionItem.TopSet.self, from: data)

        XCTAssertEqual(top.valueLabel, "BW−30 × 12")
        XCTAssertEqual(top.est_1rm, 0)
        XCTAssertNil(top.estimatedOneRepMax)
        XCTAssertEqual(
            try JSONDecoder().decode(LegacyTopSet.self, from: data).est_1rm,
            0)
    }
}

struct BodyweightProgressFixture: Decodable {
    struct Expected: Decodable {
        let weight: Double
        let is_timed: Bool
        let best_reps: Int?
        let best_duration_s: Int?
        let est_1rm: Double?
        let tonnage: Double?
        let value_label: String
        let feed_label: String
    }
    let name: String
    let catalog: [ExerciseCatalog]
    let sets: [SetLog]
    let expected_cohorts: [Expected]
    let expected_tonnage: Double?

    static func load() throws -> [Self] {
        let url = try XCTUnwrap(Bundle(for: BodyweightMetricsTests.self)
            .url(forResource: "BodyweightProgress", withExtension: "json"))
        return try JSONDecoder().decode([Self].self, from: Data(contentsOf: url))
    }
}

extension BodyweightMetricsTests {
    func testSharedProgressFixturesAndFeedRendering() throws {
        for fixture in try BodyweightProgressFixture.load() {
            let cohorts = ExerciseMetrics.cohorts(fixture.sets, catalog: fixture.catalog)
            XCTAssertEqual(cohorts.count, fixture.expected_cohorts.count, fixture.name)
            for expected in fixture.expected_cohorts {
                let cohort = try XCTUnwrap(cohorts.first {
                    $0.key.weight == expected.weight && $0.key.timed == expected.is_timed
                })
                XCTAssertEqual(cohort.bestReps, expected.best_reps, fixture.name)
                XCTAssertEqual(cohort.bestHoldSeconds, expected.best_duration_s, fixture.name)
                XCTAssertEqual(cohort.estimatedOneRepMax, expected.est_1rm, fixture.name)
                XCTAssertEqual(cohort.externalLoadVolume, expected.tonnage, fixture.name)
                XCTAssertEqual(cohort.valueLabel, expected.value_label, fixture.name)
                let wire: [String: Any] = [
                    "exercise": fixture.catalog[0].name, "weight": expected.weight,
                    "reps": cohort.top.reps, "unit": fixture.catalog[0].unit,
                    "modality": fixture.catalog[0].modality,
                    "is_timed": expected.is_timed,
                    "duration_s": expected.best_duration_s as Any? ?? NSNull(),
                    "est_1rm": expected.est_1rm ?? 0,
                    "laterality": fixture.catalog[0].laterality ?? "bilateral",
                    "load_mode": fixture.catalog[0].load_mode ?? "total",
                ]
                let feed = try JSONDecoder().decode(FeedSessionItem.TopSet.self,
                    from: JSONSerialization.data(withJSONObject: wire))
                XCTAssertEqual(feed.valueLabel, expected.feed_label, fixture.name)
                XCTAssertEqual(feed.estimatedOneRepMax, expected.est_1rm, fixture.name)
            }
        }
    }

    func testFeedUsesCohortsAndFallsBackForOlderServers() throws {
        let old = Data("""
            {"set_count":1,"top_sets":[{"exercise":"Pull-Up","weight":0,"reps":8,"est_1rm":0}]}
            """.utf8)
        let new = Data("""
            {"set_count":2,"top_sets":[],"cohort_top_sets":[
              {"exercise":"Pull-Up","weight":0,"reps":8,"modality":"bw","est_1rm":0},
              {"exercise":"Pull-Up","weight":-60,"reps":15,"modality":"bw","est_1rm":0}]}
            """.utf8)
        XCTAssertEqual(try JSONDecoder().decode(FeedSessionItem.Inner.self, from: old).displayTopSets.count, 1)
        XCTAssertEqual(try JSONDecoder().decode(FeedSessionItem.Inner.self, from: new).displayTopSets.map(\.valueLabel),
                       ["BW × 8", "BW−60 × 15"])
    }

    func testOldServerBodyweightEstimateIsSuppressedAndVariationsStaySeparate() throws {
        let data = Data("""
            {"exercise":"Pull-Up","weight":10,"reps":5,"modality":"bw","est_1rm":11.7}
            """.utf8)
        XCTAssertNil(try JSONDecoder().decode(FeedSessionItem.TopSet.self, from: data).estimatedOneRepMax)
        let fixture = try XCTUnwrap(BodyweightProgressFixture.load().first)
        let set = fixture.sets[0]
        let other = SetLog(id: "variation", session_id: set.session_id, exercise_id: "other-variation",
            template_exercise_id: nil, set_index: 9, weight: 0, reps: 99, rpe: nil,
            is_warmup: 0, logged_at: 0, duration_s: nil, is_timed: 0, deleted_at: nil)
        XCTAssertEqual(ExerciseMetrics.cohorts([set, other], catalog: fixture.catalog).count, 2)
    }
}
