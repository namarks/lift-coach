import Foundation
import XCTest
@testable import TresFort

final class PrescriptionDecodingTests: XCTestCase {
    func testAcceptedPrescriptionValuesDecodeWithoutShapeLoss() throws {
        let json = #"""
        {
          "id":"slot-a","exercise_id":"ex_pullup","exercise_name":"Pull-Up",
          "exercise_unit":"lb","order_index":0,"target_sets":3,"target_reps":5,
          "target_reps_max":8,"target_rpe":8.5,"rest_seconds":0,
          "target_weight":-12.5,"cues":null,"exercise_modality":"bw",
          "exercise_laterality":"bilateral","exercise_load_mode":"total",
          "exercise_demo_slug":"Pull-Up","target_duration_s":30,"is_warmup":0
        }
        """#.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(TemplateExercise.self, from: json)
        XCTAssertEqual(decoded.order_index, 0)
        XCTAssertEqual(decoded.target_sets, 3)
        XCTAssertEqual(decoded.target_reps, 5)
        XCTAssertEqual(decoded.target_reps_max, 8)
        XCTAssertEqual(decoded.target_rpe, 8.5)
        XCTAssertEqual(decoded.rest_seconds, 0)
        XCTAssertEqual(decoded.target_weight, -12.5)
        XCTAssertEqual(decoded.target_duration_s, 30)
    }
}
