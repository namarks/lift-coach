import Foundation

/// Values a member can correct. Identity, slot, execution class and tap time
/// are deliberately absent. An explicit nil RPE clears it on the server.
struct SetCorrectionValues: Codable, Equatable {
    let weight: Double
    let reps: Int
    let rpe: Double?
    let durationSeconds: Int?

    var isValid: Bool {
        weight.isFinite && reps >= 0
            && (rpe == nil || (rpe!.isFinite && (0...10).contains(rpe!)))
            && (durationSeconds == nil || durationSeconds! >= 0)
    }
}

struct PendingSetCorrection: Codable, Equatable, Identifiable {
    let id: String
    let setID: String
    let date: String
    var slotID: String?
    let exerciseID: String
    var sessionID: String?
    var expectedAttempt: Int?
    var expectedUpdatedAt: Int?
    /// Nil means delete; non-nil is the immutable corrected value intent.
    let values: SetCorrectionValues?
    /// Captured with the durable correction; nil on pre-focus-revision intents.
    var runnerFocusRevision: UInt64? = nil
    /// Counted group evidence survives a tombstone snapshot written before the
    /// runner checkpoint. Local only; never part of the correction request.
    var runnerGroupRepair: RunnerGroupRepair? = nil
    var deliveryState: SetIntentDeliveryState = .queued
    var failedHTTPStatus: Int?
    var isDelete: Bool { values == nil }

    var requestBody: [String: Any]? {
        guard let sessionID, let expectedAttempt, let expectedUpdatedAt else { return nil }
        var body: [String: Any] = [
            "expected_session_id": sessionID,
            "expected_attempt": expectedAttempt,
            "expected_updated_at": expectedUpdatedAt,
        ]
        if let values {
            body["weight"] = values.weight
            body["reps"] = values.reps
            body["rpe"] = values.rpe.map { $0 as Any } ?? NSNull()
            body["duration_s"] = values.durationSeconds.map { $0 as Any } ?? NSNull()
        } else {
            body["deleted"] = true
        }
        return body
    }
}

/// One pending correction per set. Further editing is disabled until this
/// immutable operation settles, preventing delayed replies from overwriting
/// a newer local edit. Unacknowledged deletes never remove visible SetLogs.
enum SetCorrectionOutboxStore {
    static func key(userID: String) -> String {
        "com.nmarkspdx.liftcoach.set-corrections.v1.\(userID)"
    }

    static func load(userID: String?, defaults: LocalPersistence) -> [PendingSetCorrection] {
        guard let userID, let data = defaults.data(forKey: key(userID: userID)) else { return [] }
        do { return try JSONDecoder().decode([PendingSetCorrection].self, from: data) }
        catch { defaults.recordInvalidData(data, forKey: key(userID: userID)); return [] }
    }

    @discardableResult
    static func enqueue(_ intent: PendingSetCorrection, userID: String?, defaults: LocalPersistence) -> Bool {
        return update(userID: userID, defaults: defaults) { pending in
            guard !pending.contains(where: { $0.setID == intent.setID }) else { return }
            pending.append(intent)
        }
    }

    @discardableResult
    static func replace(_ intent: PendingSetCorrection, userID: String?, defaults: LocalPersistence) -> Bool {
        return update(userID: userID, defaults: defaults) { pending in
            guard let i = pending.firstIndex(where: { $0.id == intent.id }) else { return }
            var replacement = intent
            // Bind once after the original create ACK; a stale callback must
            // never retarget an existing operation to a newer revision/attempt.
            if pending[i].expectedUpdatedAt != nil {
                replacement.sessionID = pending[i].sessionID
                replacement.slotID = pending[i].slotID
            }
            replacement.runnerFocusRevision = pending[i].runnerFocusRevision
            replacement.runnerGroupRepair = pending[i].runnerGroupRepair ?? intent.runnerGroupRepair
            replacement.expectedAttempt = pending[i].expectedAttempt ?? intent.expectedAttempt
            replacement.expectedUpdatedAt = pending[i].expectedUpdatedAt ?? intent.expectedUpdatedAt
            pending[i] = replacement
        }
    }

    @discardableResult
    static func remove(id: String, userID: String?, defaults: LocalPersistence) -> Bool {
        return update(userID: userID, defaults: defaults) { $0.removeAll { $0.id == id } }
    }

    @discardableResult
    static func remove(date: String, userID: String?, defaults: LocalPersistence) -> Bool {
        return update(userID: userID, defaults: defaults) { $0.removeAll { $0.date == date } }
    }

    @discardableResult
    static func clear(userID: String, defaults: LocalPersistence) -> Bool {
        return defaults.removeObject(forKey: key(userID: userID))
    }

    @discardableResult
    private static func update(userID: String?, defaults: LocalPersistence,
                               mutation: (inout [PendingSetCorrection]) -> Void) -> Bool {
        guard let userID else { return false }
        var pending = load(userID: userID, defaults: defaults)
        guard !defaults.hasFailure(forKey: key(userID: userID)) else { return false }
        let before = pending
        mutation(&pending)
        guard pending != before else { return true }
        if pending.isEmpty {
            return clear(userID: userID, defaults: defaults)
        }
        guard let data = try? JSONEncoder().encode(pending) else {
            defaults.recordWriteFailure(forKey: key(userID: userID))
            return false
        }
        return defaults.set(data, forKey: key(userID: userID))
    }
}

struct SetCorrectionResult: Decodable {
    let set: SetLog
    let session: SessionRow
    private enum CodingKeys: String, CodingKey { case session }
    init(from decoder: Decoder) throws {
        set = try SetLog(from: decoder)
        session = try decoder.container(keyedBy: CodingKeys.self).decode(SessionRow.self, forKey: .session)
    }
    init(set: SetLog, session: SessionRow) { self.set = set; self.session = session }
}
