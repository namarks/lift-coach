import XCTest
@testable import TresFort

final class BarbellLoadingTests: XCTestCase {
    func testPlatesIncludeBothSidesAndRespectSelectedBar() throws {
        let result = try XCTUnwrap(BarbellLoading.breakdown(target: 185))
        XCTAssertEqual(result.perSide, [.init(weight: 45, count: 1), .init(weight: 25, count: 1)])
        XCTAssertEqual(result.achievableWeight, 185)
        XCTAssertEqual(BarbellLoading.breakdown(target: 95, bar: 35)?.perSide,
                       [.init(weight: 25, count: 1), .init(weight: 5, count: 1)])
    }
    func testFractionalTargetIsNeverRoundedUpAndInvalidInputHasNoAdvice() {
        XCTAssertEqual(BarbellLoading.breakdown(target: 137.5)?.achievableWeight, 135)
        XCTAssertEqual(BarbellLoading.breakdown(target: 137.5)?.remainingWeight, 2.5)
        XCTAssertNil(BarbellLoading.breakdown(target: 35))
        XCTAssertNil(BarbellLoading.breakdown(target: .infinity))
        XCTAssertNil(BarbellLoading.breakdown(target: 100, bar: 0))
    }
    func testWarmupIsDeterministicBoundedAndDeduplicatesLightLoads() {
        XCTAssertEqual(BarbellLoading.warmup(target: 185).map(\.weight), [45, 90, 135])
        XCTAssertEqual(BarbellLoading.warmup(target: 185).map(\.reps), [8, 5, 3])
        XCTAssertEqual(BarbellLoading.warmup(target: 50).map(\.weight), [45])
        XCTAssertEqual(BarbellLoading.warmup(target: 45).map(\.weight), [45])
        XCTAssertTrue(BarbellLoading.warmup(target: 25).isEmpty)
    }
}
