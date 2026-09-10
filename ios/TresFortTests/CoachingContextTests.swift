import XCTest
@testable import TresFort

final class CoachingContextTests: XCTestCase {
    struct Fixture: Decodable {
        struct Conflict: Decodable {
            let name: String
            let lift_date: String
            let events: [ExternalEvent]
            let expected: String
        }
        let catalog: [ExerciseCatalog]
        let sets: [SetLog]
        let session: SessionRow
        let expected_session: CoachingContext.Session
        let meta: [String: JSONValue]
        let conflicts: [Conflict]
    }
    func fixture() throws -> Fixture {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "CoachingContext", withExtension: "json"))
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }
    func testSharedSemanticProjectionAndAuthoredMetadata() throws {
        let f = try fixture()
        XCTAssertEqual(CoachingContext.session(f.session, sets: f.sets, catalog: f.catalog), f.expected_session)
        let meta = String(decoding: try JSONEncoder().encode(f.meta), as: UTF8.self)
        XCTAssertEqual(CoachingContext.planMeta(meta), f.meta)
        XCTAssertTrue(CoachingContext.planMeta("{invalid").values.allSatisfy { $0 == .null })
    }
    func testSharedSchedulingHeuristicUnknownAndThresholdFixtures() throws {
        for c in try fixture().conflicts {
            XCTAssertEqual(RideConflict.severity(forLiftDate: c.lift_date, hasLift: { $0 == c.lift_date },
                ridesOn: { date in c.events.filter { $0.date == date } }).rawValue, c.expected, c.name)
        }
    }
    func testRecentAndLastCompletedKeepSameSessionAndDoNotLetFutureOrDiscardedRowsHideIt() throws {
        let f = try fixture()
        var skipped = f.session
        skipped = SessionRow(id: "skip", date: "2026-09-10", status: "skipped", workout_id: nil)
        let future = SessionRow(id: "future", date: "2026-09-12", status: "planned", workout_id: nil)
        let discarded = SessionRow(id: "discard", date: "2026-09-11", status: "discarded", workout_id: nil)
        let rows = [future, discarded, f.session, skipped]
        XCTAssertEqual(CoachingContext.recent(rows, through: "2026-09-11").map(\.id), ["skip", "recent"])
        let last = try XCTUnwrap(CoachingContext.lastCompleted(rows, through: "2026-09-11"))
        XCTAssertEqual(CoachingContext.session(last, sets: f.sets, catalog: f.catalog), f.expected_session)
    }
    func testDeliveredBodyweightCohortsKeepTheirRecordedConditions() throws {
        for f in try BodyweightProgressFixture.load() {
            let row = SessionRow(id: f.name, date: "2026-09-09", status: "completed", workout_id: nil)
            let result = CoachingContext.session(row, sets: f.sets, catalog: f.catalog)
            let live = f.sets.filter { $0.deleted_at == nil && $0.is_warmup == 0 }
            XCTAssertEqual(result.sets.count, f.expected_cohorts.count, f.name)
            XCTAssertEqual(result.external_load_volume.first?.value, f.expected_tonnage, f.name)
            for set in result.sets {
                let original = try XCTUnwrap(live.first { $0.id == set.id })
                XCTAssertEqual(set.weight, original.weight, f.name)
                XCTAssertEqual(set.duration_s, set.is_timed ? original.duration_s ?? original.reps : nil, f.name)
            }
        }
    }
}
