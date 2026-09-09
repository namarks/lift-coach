import Foundation

/// A day is edited and previewed in indivisible prescription blocks. Member
/// order is the stored day order; labels are derived, never persisted.
struct ExerciseGroupBlock: Identifiable {
    let members: [TemplateExercise]
    let letter: String?

    var groupID: String? { members.first?.group_id }
    var id: String { groupID.map { "group:\($0)" } ?? "slot:\(members[0].id)" }
    var isGroup: Bool { groupID != nil }
    var isWarmup: Bool { members.allSatisfy(\.isWarmup) }
    var title: String { "\(members.count == 2 ? "Superset" : "Circuit") \(letter ?? "")" }
    var rounds: Int { members[0].target_sets }
    var roundRest: Int { members[0].group_rest_seconds ?? 0 }
    var transitionRest: Int { members[0].group_transition_seconds ?? 0 }
    func memberLabel(at index: Int) -> String { "\(letter ?? "")\(index + 1)" }

    static func blocks(_ exercises: [TemplateExercise]) -> [Self] {
        var result: [Self] = []
        var index = 0
        var groupNumber = 0
        while index < exercises.count {
            let first = exercises[index]
            var end = index + 1
            if let groupID = first.group_id {
                while end < exercises.count && exercises[end].group_id == groupID { end += 1 }
                groupNumber += 1
            }
            result.append(Self(members: Array(exercises[index..<end]),
                               letter: first.group_id == nil ? nil : label(groupNumber)))
            index = end
        }
        return result
    }

    /// Selection never absorbs part of an existing group or skips a slot.
    static func selectedMembers(_ ids: Set<String>, in exercises: [TemplateExercise]) -> [TemplateExercise]? {
        guard ids.count >= 2 else { return nil }
        let indices = exercises.indices.filter { ids.contains(exercises[$0].id) }
        guard indices.count == ids.count, let first = indices.first, let last = indices.last,
              last - first + 1 == indices.count,
              indices.allSatisfy({ exercises[$0].group_id == nil }) else { return nil }
        return indices.map { exercises[$0] }
    }

    /// The API destination is an index in the resulting flattened day.
    static func slotDestination(of blockID: String, in blocks: [Self]) -> Int? {
        guard let index = blocks.firstIndex(where: { $0.id == blockID }) else { return nil }
        return blocks.prefix(index).reduce(0) { $0 + $1.members.count }
    }

    private static func label(_ number: Int) -> String {
        var value = number, result = ""
        repeat {
            value -= 1
            result = String(UnicodeScalar(65 + value % 26)!) + result
            value /= 26
        } while value > 0
        return result
    }
}
