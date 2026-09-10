import Foundation
import XCTest
@testable import TresFort

@MainActor
final class GroupStateSnapshotTests: XCTestCase {
    private let userID = "group-cache-user"
    private let groupID = "b157648a-67c1-4e9f-9dde-a8b0db8a4aa0"

    private func withDefaults(_ body: (LocalPersistence, String) throws -> Void) rethrows {
        let suite = "GroupStateSnapshotTests.\(UUID().uuidString)"
        let defaults = LocalPersistence(suiteName: suite)!
        defer {
            StateSnapshotStore.clear(userID: userID, defaults: defaults)
            defaults.removePersistentDomain(forName: suite)
        }
        try body(defaults, suite)
    }

    private func plan(grouped: Bool = true, version: Int = 7, meta: String? = nil) -> PlanTree {
        let slots = ["Push-up", "Squat"].enumerated().map { index, name in
            TemplateExercise(
                id: "slot-\(index)", exercise_id: "exercise-\(index)",
                exercise_name: name, exercise_unit: "lb", order_index: index,
                target_sets: 2, target_reps: 10, target_reps_max: nil,
                target_rpe: nil, rest_seconds: grouped ? (index == 0 ? 45 : 90) : 30,
                target_weight: nil, cues: nil, exercise_modality: "bw",
                exercise_laterality: nil, exercise_load_mode: nil,
                exercise_demo_slug: nil, target_duration_s: nil, is_warmup: 1,
                group_id: grouped ? groupID : nil,
                group_rest_seconds: grouped ? 30 : nil,
                group_transition_seconds: grouped ? 0 : nil)
        }
        return PlanTree(id: "plan-a", name: "Plan", version: version,
            workouts: [Workout(id: "day-a", name: "Warm-up", day_label: "A",
                order_index: 0, exercises: slots)], meta: meta)
    }

    private func response(
        plan: PlanTree?, version: Int = 7, proof: Int? = 1,
        sessions: [SessionRow] = [], serverTime: Int = 2_000_000_100_000
    ) -> StateResponse {
        StateResponse(plan: plan, plan_version: version, sessions: sessions,
            sets: [], external_events: [], external_activities: [], activities: [],
            server_time: serverTime, externalSyncCursorsVersion: 2,
            planGroupsVersion: proof)
    }

    private func object<T: Encodable>(_ value: T) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(value)) as? [String: Any])
    }

    private func persistedEnvelope(_ defaults: LocalPersistence) throws -> [String: Any] {
        let data = try XCTUnwrap(defaults.data(forKey: StateSnapshotStore.scopedKey(userID: userID)))
        let json = try XCTUnwrap(StateSnapshotStore.decodedEnvelope(data))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
    }

    /// Model the shipped envelope before group certification existed, retaining
    /// independent collection cursors and its flattened same-version plan.
    private func installLegacyEnvelope(
        _ defaults: LocalPersistence, wireProof: Int? = nil
    ) throws -> StateSyncWatermarks {
        let session = SessionRow(id: "session-a", date: "2033-05-18",
            status: "in_progress", workout_id: "day-a", updated_at: 1_000)
        let legacy = response(plan: plan(grouped: false), proof: wireProof,
            sessions: [session], serverTime: 2_000_000_000_000)
        let watermarks = StateSyncWatermarks.next(after: legacy)
        let envelope: [String: Any] = [
            "revision": 11, "state": try object(legacy), "invalidated": false,
            "latestFullRequestRevision": 11, "mutationGeneration": 0,
            "watermarks": try object(watermarks), "setsCommittedThrough": legacy.server_time,
        ]
        defaults.set(try JSONSerialization.data(withJSONObject: envelope),
            forKey: StateSnapshotStore.scopedKey(userID: userID))
        return watermarks
    }

    func testGroupFieldsDecodeAbsentNullAndPresentWithoutChangingOrdinaryRest() throws {
        var slot = try object(plan().workouts[0].exercises[0])
        let keys = ["group_id", "group_rest_seconds", "group_transition_seconds"]
        for mode in ["absent", "null", "present"] {
            if mode == "absent" { keys.forEach { slot.removeValue(forKey: $0) } }
            if mode == "null" { keys.forEach { slot[$0] = NSNull() } }
            if mode == "present" {
                slot["group_id"] = groupID
                slot["group_rest_seconds"] = 30
                slot["group_transition_seconds"] = 0
            }
            let decoded = try JSONDecoder().decode(TemplateExercise.self,
                from: JSONSerialization.data(withJSONObject: slot))
            XCTAssertEqual(decoded.rest_seconds, 45)
            XCTAssertEqual(decoded.group_id, mode == "present" ? groupID : nil)
            XCTAssertEqual(decoded.group_rest_seconds, mode == "present" ? 30 : nil)
            XCTAssertEqual(decoded.group_transition_seconds, mode == "present" ? 0 : nil)
            XCTAssertEqual(try JSONDecoder().decode(TemplateExercise.self,
                from: JSONEncoder().encode(decoded)), decoded)
        }
    }

    func testLegacyEnvelopeOnlyResetsPlanCursorEvenIfCachedWireClaimExists() throws {
        for cachedProof: Int? in [nil, 1] {
            try withDefaults { defaults, _ in
                let previous = try installLegacyEnvelope(defaults, wireProof: cachedProof)
                XCTAssertEqual(StateSnapshotStore.load(userID: userID, defaults: defaults)?
                    .state.plan?.workouts[0].exercises[0].rest_seconds, 30)
                let ticket = try XCTUnwrap(StateSnapshotStore.reserveStateRequest(
                    userID: userID, defaults: defaults))
                XCTAssertEqual(ticket.watermarks.planVersion, 0)
                XCTAssertEqual(ticket.watermarks.setsSince, previous.setsSince)
                XCTAssertEqual(ticket.watermarks.eventsSince, previous.eventsSince)
                XCTAssertEqual(ticket.watermarks.activitiesSince, previous.activitiesSince)
                XCTAssertEqual(ticket.watermarks.logSince, previous.logSince)
                XCTAssertNil(try persistedEnvelope(defaults)["planGroupsVersion"])
            }
        }
    }

    func testLivePlanOnlyUpgradeReplacesSameVersionFlatPlanAndKeepsOtherCollections() throws {
        try withDefaults { defaults, suite in
            _ = try installLegacyEnvelope(defaults)
            let ticket = try XCTUnwrap(StateSnapshotStore.reserveStateRequest(
                userID: userID, defaults: defaults))
            XCTAssertNotEqual(ticket.watermarks, .fullReload)
            let live = response(plan: plan())
            XCTAssertNil(StateSnapshotStore.commitFullState(live, ticket: ticket, defaults: defaults))
            let committed = try XCTUnwrap(StateSnapshotStore.commitStateResponse(
                live, ticket: ticket, defaults: defaults))
            XCTAssertEqual(committed.state.sessions.map(\.id), ["session-a"])
            XCTAssertEqual(committed.state.plan, plan())
            XCTAssertEqual(committed.watermarks?.planVersion, 7)
            XCTAssertEqual(try persistedEnvelope(defaults)["planGroupsVersion"] as? Int, 1)
            // An actual committed certificate survives a cold envelope decode.
            let reopened = LocalPersistence(suiteName: suite)!
            let next = try XCTUnwrap(StateSnapshotStore.reserveStateRequest(
                userID: userID, defaults: reopened))
            XCTAssertEqual(next.watermarks.planVersion, 7)
        }
    }

    func testRawLegacyStateWireClaimCannotCertifyTheMigratedEnvelope() throws {
        try withDefaults { defaults, _ in
            let legacy = response(plan: plan(grouped: false))
            defaults.set(try JSONEncoder().encode(legacy),
                forKey: StateSnapshotStore.scopedKey(userID: userID))
            let loaded = try XCTUnwrap(StateSnapshotStore.load(userID: userID, defaults: defaults))
            XCTAssertEqual(loaded.state.planGroupsVersion, 1)
            XCTAssertEqual(loaded.state.plan, plan(grouped: false))
            XCTAssertEqual(StateSnapshotStore.reserveStateRequest(
                userID: userID, defaults: defaults)?.watermarks, .fullReload)
            XCTAssertNil(try persistedEnvelope(defaults)["planGroupsVersion"])
        }
    }

    func testUnsupportedProofAndMismatchedTreeVersionCannotCertifyLiveResponse() throws {
        for (proof, treeVersion) in [(1, 8), (0, 7), (-1, 7)] {
            try withDefaults { defaults, _ in
                _ = try installLegacyEnvelope(defaults)
                let ticket = try XCTUnwrap(StateSnapshotStore.reserveStateRequest(
                    userID: userID, defaults: defaults))
                let committed = try XCTUnwrap(StateSnapshotStore.commitStateResponse(
                    response(plan: plan(version: treeVersion), version: 7, proof: proof),
                    ticket: ticket, defaults: defaults))
                XCTAssertEqual(committed.watermarks?.planVersion, 0)
                XCTAssertGreaterThan(committed.watermarks?.setsSince ?? 0, 0)
                XCTAssertNil(try persistedEnvelope(defaults)["planGroupsVersion"])
                XCTAssertEqual(StateSnapshotStore.reserveStateRequest(
                    userID: userID, defaults: defaults)?.watermarks.planVersion, 0)
            }
        }
    }

    func testThinOrFailedUpgradeCannotCertifyOrEraseTheOfflinePlan() throws {
        try withDefaults { defaults, _ in
            _ = try installLegacyEnvelope(defaults)
            let ticket = try XCTUnwrap(StateSnapshotStore.reserveStateRequest(
                userID: userID, defaults: defaults))
            XCTAssertNil(StateSnapshotStore.commitStateResponse(
                response(plan: nil), ticket: ticket, defaults: defaults))
            XCTAssertEqual(StateSnapshotStore.load(userID: userID, defaults: defaults)?
                .state.plan, plan(grouped: false))
            var malformed = try object(response(plan: plan()))
            malformed["plan_groups_version"] = "1"
            XCTAssertThrowsError(try JSONDecoder().decode(StateResponse.self,
                from: JSONSerialization.data(withJSONObject: malformed)))
            XCTAssertTrue(StateSnapshotStore.isCurrent(ticket, defaults: defaults))
            XCTAssertNil(try persistedEnvelope(defaults)["planGroupsVersion"])
            XCTAssertEqual(StateSnapshotStore.reserveStateRequest(
                userID: userID, defaults: defaults)?.watermarks.planVersion, 0)
        }
    }

    func testSupersededLiveProofCannotUpgradeNewerLegacyResponse() throws {
        try withDefaults { defaults, _ in
            _ = try installLegacyEnvelope(defaults)
            let old = try XCTUnwrap(StateSnapshotStore.reserveStateRequest(userID: userID, defaults: defaults))
            let new = try XCTUnwrap(StateSnapshotStore.reserveStateRequest(userID: userID, defaults: defaults))
            XCTAssertNil(StateSnapshotStore.commitStateResponse(response(plan: plan()), ticket: old, defaults: defaults))
            XCTAssertNotNil(StateSnapshotStore.commitStateResponse(
                response(plan: plan(grouped: false), proof: nil), ticket: new, defaults: defaults))
            XCTAssertNil(try persistedEnvelope(defaults)["planGroupsVersion"])
            XCTAssertEqual(StateSnapshotStore.reserveStateRequest(
                userID: userID, defaults: defaults)?.watermarks.planVersion, 0)
        }
    }

    func testUnchangedDeltaAndAcknowledgementRetainOnlyExistingCertificate() throws {
        try withDefaults { defaults, _ in
            StateSnapshotStore.save(response(plan: plan()), userID: userID, defaults: defaults)
            let delta = try XCTUnwrap(StateSnapshotStore.reserveStateRequest(userID: userID, defaults: defaults))
            XCTAssertNotNil(StateSnapshotStore.commitStateResponse(
                response(plan: nil, proof: nil), ticket: delta, defaults: defaults))
            let acknowledged = SessionRow(id: "session-a", date: "2033-05-18",
                status: "complete", workout_id: "day-a", updated_at: 2_000_000_100_010)
            XCTAssertNotNil(StateSnapshotStore.mergeAcknowledgement(
                userID: userID, fallback: response(plan: plan(grouped: false)), defaults: defaults
            ) { current in
                response(plan: current.plan, proof: nil, sessions: [acknowledged])
            })
            XCTAssertEqual(try persistedEnvelope(defaults)["planGroupsVersion"] as? Int, 1)
            XCTAssertEqual(StateSnapshotStore.reserveStateRequest(
                userID: userID, defaults: defaults)?.watermarks.planVersion, 7)

            // An ACK may retain an unchanged tree; even its own wire claim may
            // not certify a replacement tree or a fallback after cache loss.
            XCTAssertNotNil(StateSnapshotStore.mergeAcknowledgement(
                userID: userID, fallback: response(plan: plan()), defaults: defaults
            ) { _ in response(plan: plan(version: 8), version: 8) })
            XCTAssertNil(try persistedEnvelope(defaults)["planGroupsVersion"])
            XCTAssertEqual(StateSnapshotStore.reserveStateRequest(
                userID: userID, defaults: defaults)?.watermarks.planVersion, 0)
            StateSnapshotStore.clear(userID: userID, defaults: defaults)
            XCTAssertNotNil(StateSnapshotStore.mergeAcknowledgement(
                userID: userID, fallback: response(plan: plan()), defaults: defaults, transform: { $0 }))
            XCTAssertNil(try persistedEnvelope(defaults)["planGroupsVersion"])
        }
    }

    func testReplacementWithoutProofResetsPlanWhileLiveVersionZeroClearsIt() throws {
        try withDefaults { defaults, _ in
            StateSnapshotStore.save(response(plan: plan()), userID: userID, defaults: defaults)
            let ticket = try XCTUnwrap(StateSnapshotStore.reserveStateRequest(userID: userID, defaults: defaults))
            let replacement = response(plan: plan(grouped: false, version: 8), version: 8, proof: nil)
            let committed = try XCTUnwrap(StateSnapshotStore.commitStateResponse(
                replacement, ticket: ticket, defaults: defaults))
            XCTAssertEqual(committed.state.plan?.version, 8)
            XCTAssertEqual(committed.watermarks?.planVersion, 0)
            XCTAssertGreaterThan(committed.watermarks?.setsSince ?? 0, 0)
            let reload = try XCTUnwrap(StateSnapshotStore.reserveStateRequest(userID: userID, defaults: defaults))
            let empty = try XCTUnwrap(StateSnapshotStore.commitStateResponse(
                response(plan: nil, version: 0, proof: nil), ticket: reload, defaults: defaults))
            XCTAssertNil(empty.state.plan)
            XCTAssertEqual(empty.watermarks?.planVersion, 0)
        }
    }

    func testTreeChangingAcknowledgementCannotRetainCertificateAtSameVersion() throws {
        try withDefaults { defaults, _ in
            StateSnapshotStore.save(response(plan: plan()), userID: userID, defaults: defaults)
            let changedTree = plan(grouped: false)
            let committed = try XCTUnwrap(StateSnapshotStore.mergeAcknowledgement(
                userID: userID, fallback: response(plan: plan()), defaults: defaults
            ) { _ in response(plan: changedTree) })
            XCTAssertEqual(committed.state.plan?.id, "plan-a")
            XCTAssertEqual(committed.state.plan_version, 7)
            XCTAssertEqual(committed.state.plan, changedTree)
            XCTAssertNil(try persistedEnvelope(defaults)["planGroupsVersion"])
            XCTAssertEqual(StateSnapshotStore.reserveStateRequest(
                userID: userID, defaults: defaults)?.watermarks.planVersion, 0)
        }
    }

    func testExplicitReloadAndInvalidationDropCertificationAndRejectOldTickets() throws {
        try withDefaults { defaults, _ in
            for removePresentation in [false, true] {
                StateSnapshotStore.save(response(plan: plan()), userID: userID, defaults: defaults)
                let old = try XCTUnwrap(StateSnapshotStore.reserveStateRequest(userID: userID, defaults: defaults))
                if removePresentation {
                    XCTAssertTrue(StateSnapshotStore.invalidate(userID: userID, defaults: defaults))
                } else {
                    XCTAssertTrue(StateSnapshotStore.requireFullReload(userID: userID, defaults: defaults))
                }
                XCTAssertNil(try persistedEnvelope(defaults)["planGroupsVersion"])
                XCTAssertNil(StateSnapshotStore.commitStateResponse(response(plan: plan()), ticket: old, defaults: defaults))
                XCTAssertEqual(StateSnapshotStore.reserveStateRequest(userID: userID, defaults: defaults)?.watermarks, .fullReload)
            }
        }
    }

    func testOversizedLivePlanKeepsGroupsButColdMarkerNeverCertifiesIt() throws {
        try withDefaults { defaults, suite in
            var generator: UInt64 = 0x123456789abcdef
            var noise = Data(count: 5 * 1_024 * 1_024)
            noise.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
                for index in bytes.indices {
                    generator ^= generator << 13
                    generator ^= generator >> 7
                    generator ^= generator << 17
                    bytes[index] = UInt8(truncatingIfNeeded: generator)
                }
            }
            let hugePlan = plan(meta: noise.base64EncodedString())
            let live = response(plan: hugePlan)
            XCTAssertNil(StateSnapshotStore.encodedEnvelope(try JSONEncoder().encode(live)))
            StateSnapshotStore.save(live, userID: userID, defaults: defaults)
            XCTAssertEqual(StateSnapshotStore.load(userID: userID, defaults: defaults)?.state.plan, hugePlan)
            XCTAssertNotNil(StateSnapshotStore.mergeAcknowledgement(
                userID: userID, fallback: response(plan: plan(grouped: false)), defaults: defaults, transform: { $0 }))
            XCTAssertEqual(StateSnapshotStore.load(userID: userID, defaults: defaults)?
                .state.plan?.workouts[0].exercises[0].group_id, groupID)
            let marker = try persistedEnvelope(defaults)
            XCTAssertNil(marker["state"])
            XCTAssertNil(marker["planGroupsVersion"])
            XCTAssertEqual(marker["invalidated"] as? Bool, true)
            let coldDefaults = LocalPersistence(suiteName: suite)!
            XCTAssertNil(StateSnapshotStore.load(userID: userID, defaults: coldDefaults))
            XCTAssertEqual(StateSnapshotStore.reserveStateRequest(
                userID: userID, defaults: coldDefaults)?.watermarks, .fullReload)
        }
    }
}
