import XCTest
@testable import TresFort

final class WorkoutSummaryTests: XCTestCase {
    func testServerCompletionFixtureDecodesWithoutRecalculatingRecords() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "WorkoutCompletion", withExtension: "json"))
        let summary = try JSONDecoder().decode(WorkoutSummary.self, from: Data(contentsOf: url))
        XCTAssertTrue(summary.final)
        XCTAssertEqual(summary.working_sets, 4)
        XCTAssertEqual(summary.external_load_volume, 225)
        XCTAssertEqual(summary.records.count, 1)
        XCTAssertEqual(summary.records.first?.label, "BW−30 lb assist · 12 reps")
        XCTAssertEqual(summary.records.first?.previous, 10)
        XCTAssertFalse(summary.targets_available)
        XCTAssertEqual(summary.cohorts.last?.label, "Strict BW · 45s")
    }
}
