import XCTest
@testable import TresFort

@MainActor
final class ActivityTimeTests: XCTestCase {
    struct Fixture: Decodable { let name: String; let utc: String; let zone: String; let local: String }

    func testSourceTimezoneCivilDatesAcrossTravelAndBothDSTTransitions() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "ActivityTime", withExtension: "json"))
        let rows = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: url))
        let iso = ISO8601DateFormatter()
        for row in rows {
            let start = try XCTUnwrap(iso.date(from: row.utc))
            let zone = try XCTUnwrap(TimeZone(identifier: row.zone))
            let (date, localMs) = HealthKitSyncModel.civilDateAndLocalMs(start, timeZone: zone)
            XCTAssertEqual(date, String(row.local.prefix(10)), row.name)
            let expectedLocal = try XCTUnwrap(iso.date(from: row.local))
            XCTAssertEqual(localMs, Int(expectedLocal.timeIntervalSince1970 * 1000), row.name)
        }
    }

    func testSourceInstantRemainsSeparateFromCivilOrderingProxyInPush() throws {
        let body = HealthKitActivityPush(id: "sample", date: "2026-06-18", start_date_local_ms: 1,
            start_date_utc_ms: 2, source_timezone: "America/Los_Angeles", kind: "strength", name: nil,
            moving_time_sec: nil, elapsed_time_sec: nil, distance_m: nil, average_hr: nil,
            max_hr: nil, calories: nil, elevation_gain_m: nil, raw: nil).jsonBody
        XCTAssertEqual(body["start_date_local_ms"] as? Int, 1)
        XCTAssertEqual(body["start_date_utc_ms"] as? Int, 2)
        XCTAssertEqual(body["source_timezone"] as? String, "America/Los_Angeles")
    }
}
