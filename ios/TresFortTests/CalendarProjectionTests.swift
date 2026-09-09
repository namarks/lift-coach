import XCTest
@testable import TresFort

final class CalendarProjectionTests: XCTestCase {
    func testSharedTypeScriptSwiftFixtures() throws {
        struct Fixtures: Decodable {
            struct Weekday: Decodable { let date: String; let weekday: String }
            struct Projection: Decodable {
                struct Trip: Decodable {
                    let id: String; let start: String; let end: String
                    let type: String; let can_train_light: Bool
                }
                let name: String; let date: String; let today: String
                let week: [String: String?]; let live: [String]
                let sessions: [SessionRow]; let trips: [Trip]
                let expected_status: String; let expected_suppressed: Bool
            }
            let weekdays: [Weekday]; let projections: [Projection]
        }
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "CalendarProjection", withExtension: "json"))
        let fixtures = try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: url))
        for fixture in fixtures.weekdays {
            XCTAssertEqual(CalendarProjection.weekdayKey(forDateString: fixture.date), fixture.weekday, fixture.date)
        }
        for fixture in fixtures.projections {
            let projection = CalendarProjection.project(dateString: fixture.date, today: fixture.today,
                sessionByDate: Dictionary(uniqueKeysWithValues: fixture.sessions.map { ($0.date, $0) }),
                schedule: PlanSchedule(version: 1, week: fixture.week), templateIDs: Set(fixture.live),
                trips: fixture.trips.map { TripRange(id: $0.id, start: $0.start, end: $0.end,
                    type: $0.type, canTrainLight: $0.can_train_light) })
            let status: String
            switch projection {
            case .session(let value, _): status = value
            case .projected: status = "projected"
            case .rest: status = "rest"
            case .unavailable: status = "unavailable"
            case .light: status = "light"
            case .none: status = "none"
            }
            XCTAssertEqual(status, fixture.expected_status, fixture.name)
            XCTAssertEqual(projection.suppressesScheduleAndEndurance, fixture.expected_suppressed, fixture.name)
        }
    }

    private let today = "2026-05-18"
    private let blackout = TripRange(
        id: "trip-blackout",
        start: "2026-05-20",
        end: "2026-05-20",
        type: "travel",
        canTrainLight: false)
    private let schedule = PlanSchedule(
        version: 1,
        week: ["wed": "d_pull"])

    private func session(status: String) -> SessionRow {
        SessionRow(
            id: "session-\(status)",
            date: "2026-05-20",
            status: status,
            // The schedule projects d_pull. A real d_push session proves the
            // result came from the session rather than schedule projection.
            workout_id: "d_push")
    }

    func testBlackoutKeepsOnlyRealLoggedSessionsVisible() {
        for status in ["in_progress", "completed"] {
            let real = session(status: status)
            let projection = CalendarProjection.project(
                dateString: real.date,
                today: today,
                sessionByDate: [real.date: real],
                schedule: schedule,
                templateIDs: ["d_push", "d_pull"],
                trips: [blackout])

            XCTAssertEqual(
                projection,
                .session(
                    status: status,
                    hardBlackoutTripType: "travel"),
                "\(status) is evidence that training happened and must survive the blackout")
            XCTAssertTrue(projection.suppressesScheduleAndEndurance)
        }
    }

    func testBlackoutSuppressesPlannedSkippedDiscardedAndUnknownSessions() {
        for status in ["planned", "skipped", "discarded", "unknown_non_training"] {
            let real = session(status: status)

            XCTAssertEqual(
                CalendarProjection.project(
                    dateString: real.date,
                    today: today,
                    sessionByDate: [real.date: real],
                    schedule: schedule,
                    templateIDs: ["d_push", "d_pull"],
                    trips: [blackout]),
                .unavailable(tripType: "travel"),
                "\(status) must not defeat a hard blackout")
        }
    }

    func testBlackoutSuppressesScheduleWhenThereIsNoRealSession() {
        XCTAssertEqual(
            CalendarProjection.project(
                dateString: "2026-05-20",
                today: today,
                sessionByDate: [:],
                schedule: schedule,
                templateIDs: ["d_pull"],
                trips: [blackout]),
            .unavailable(tripType: "travel"))
    }

    func testBlackoutSessionRetainsNullTemplateWithoutEnablingScheduleFallback() {
        let real = SessionRow(
            id: "session-null-template",
            date: "2026-05-20",
            status: "in_progress",
            workout_id: nil)

        let projection = CalendarProjection.project(
            dateString: real.date,
            today: today,
            sessionByDate: [real.date: real],
            schedule: schedule,
            templateIDs: ["d_pull"],
            trips: [blackout])

        XCTAssertEqual(
            projection,
            .session(
                status: "in_progress",
                hardBlackoutTripType: "travel"))
        XCTAssertTrue(projection.suppressesScheduleAndEndurance)
    }

    func testOrdinarySessionDoesNotSuppressEndurance() {
        let real = session(status: "completed")
        let projection = CalendarProjection.project(
            dateString: real.date,
            today: today,
            sessionByDate: [real.date: real],
            schedule: schedule,
            templateIDs: ["d_push", "d_pull"])

        XCTAssertEqual(projection, .session(status: "completed"))
        XCTAssertFalse(projection.suppressesScheduleAndEndurance)
    }

    func testHardBlackoutSurvivingLiftDoesNotCreateRideConflict() {
        let real = session(status: "completed")
        let blackoutProjection = CalendarProjection.project(
            dateString: real.date,
            today: today,
            sessionByDate: [real.date: real],
            schedule: schedule,
            templateIDs: ["d_push", "d_pull"],
            trips: [blackout])
        let ordinaryProjection = CalendarProjection.project(
            dateString: real.date,
            today: today,
            sessionByDate: [real.date: real],
            schedule: schedule,
            templateIDs: ["d_push", "d_pull"])

        XCTAssertFalse(RideConflict.dateHasLift(blackoutProjection))
        XCTAssertTrue(RideConflict.dateHasLift(ordinaryProjection))
    }
}
