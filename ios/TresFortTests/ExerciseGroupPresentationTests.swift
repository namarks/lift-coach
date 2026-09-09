import XCTest
@testable import TresFort

final class ExerciseGroupPresentationTests: XCTestCase {
    private struct Fixture: Decodable {
        let slots: [TemplateExercise]
    }

    private func slots() throws -> [TemplateExercise] {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "ExerciseGroups", withExtension: "json"))
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url)).slots
    }

    func testSelectionRequiresAdjacentOrdinarySlotsAndCannotAbsorbPartOfGroup() throws {
        var slots = try slots()
        XCTAssertNil(ExerciseGroupBlock.selectedMembers([slots[0].id], in: slots))
        XCTAssertNil(ExerciseGroupBlock.selectedMembers([slots[0].id, slots[2].id], in: slots))
        XCTAssertEqual(ExerciseGroupBlock.selectedMembers([slots[1].id, slots[0].id], in: slots)?.map(\.id),
                       Array(slots.prefix(2)).map(\.id))
        slots[0].group_id = "warmup"
        slots[1].group_id = "warmup"
        XCTAssertNil(ExerciseGroupBlock.selectedMembers([slots[1].id, slots[2].id], in: slots))
        XCTAssertNil(ExerciseGroupBlock.selectedMembers([slots[0].id, slots[1].id], in: slots))
    }

    func testGroupCardsAndBlockMovesPreserveMemberOrderAndIndividualRests() throws {
        var slots = try slots()
        for i in 0..<2 {
            slots[i].group_id = "warmup"
            slots[i].group_rest_seconds = 30
            slots[i].group_transition_seconds = 0
        }
        for i in 2..<4 {
            slots[i].group_id = "working"
            slots[i].group_rest_seconds = 60
            slots[i].group_transition_seconds = 15
        }
        let blocks = ExerciseGroupBlock.blocks(slots)
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0].title, "Superset A")
        XCTAssertTrue(blocks[0].isWarmup)
        XCTAssertFalse(blocks[1].isWarmup)
        XCTAssertEqual(blocks[1].memberLabel(at: 1), "B2")
        XCTAssertEqual(blocks[1].roundRest, 60)
        XCTAssertEqual(blocks[1].transitionRest, 15)
        let reordered = [blocks[1], blocks[0]]
        XCTAssertEqual(ExerciseGroupBlock.slotDestination(of: blocks[0].id, in: reordered), 2)
        XCTAssertEqual(ExerciseGroupBlock.slotDestination(of: blocks[1].id, in: reordered), 0)
        XCTAssertEqual(reordered.flatMap(\.members).map(\.rest_seconds), [120, 75, 45, 90])
        for i in slots.indices {
            slots[i].group_id = nil
            slots[i].group_rest_seconds = nil
            slots[i].group_transition_seconds = nil
        }
        XCTAssertEqual(ExerciseGroupBlock.blocks(slots).count, 4)
        XCTAssertEqual(slots.map(\.rest_seconds), [45, 90, 120, 75])
    }
}
