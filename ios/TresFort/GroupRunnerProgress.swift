import Foundation

/// A round is derived from durable physical-set identities, never advanced by
/// a transport callback. Replacing a queued UUID with its ACK is a no-op here.
struct GroupRunnerProgress: Codable, Equatable {
    struct Member: Codable, Equatable {
        let id: String
        let target: Int
        let completedIDs: Set<String>
        let skipped: Bool
    }
    let id: String
    let members: [Member]

    var executable: [Member] { members.filter { !$0.skipped } }
    var nextMemberID: String? {
        let incomplete = executable.filter { $0.completedIDs.count < $0.target }
        guard let minimum = incomplete.map({ $0.completedIDs.count }).min() else { return nil }
        return incomplete.first { $0.completedIDs.count == minimum }?.id
    }
    var completedRounds: Int { executable.map { min($0.completedIDs.count, $0.target) }.min() ?? 0 }
    var round: Int { completedRounds + 1 }
}
