import Foundation
import XCTest
@testable import TresFort

@MainActor
final class GroupSafetyTests: XCTestCase {
    private final class TokenStore: AppTokenStore {
        var token: String?
        func save(_ token: String) { self.token = token }
        func load() -> String? { token }
        func clear() { token = nil }
    }

    func testReportDraftContainsOnlyCategoryAndReferencesAndEncodesURLCharacters() throws {
        let report = GroupReport(groupID: "group-reference", memberID: "member-reference",
                                 itemID: "intervals:activity:42", itemType: "ride")
        let url = try XCTUnwrap(report.emailURL(reason: .threats))
        let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(parts.scheme, "mailto")
        XCTAssertEqual(parts.path, "nick@tresfort.app")
        let query = Dictionary(uniqueKeysWithValues: (parts.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(query["body"], "Category: Threats\nGroup: group-reference\nMember: member-reference\nItem: ride / intervals:activity:42\n\nPlease describe the concern before sending:\n")
        XCTAssertEqual(Set(query.keys), ["subject", "body"])
        XCTAssertFalse(url.absoluteString.contains("\n"))
    }

    func testAcknowledgedBlockCannotBeUndoneByAnEarlierRosterResponse() async throws {
        let suite = "GroupSafetyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(LocalPersistence(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let auth = AuthModel(tokenStore: TokenStore(), defaults: defaults)
        auth.userID = "user-a"
        let payload = try JSONSerialization.data(withJSONObject: ["sub": "user-a", "exp": 4_000_000_000])
        auth.jwt = "header." + payload.base64EncodedString().replacingOccurrences(of: "=", with: "") + ".signature"
        var oldRead: CheckedContinuation<[GroupSummary], Error>?
        var calls = 0
        let model = GroupModel(auth: auth, defaults: defaults, groupLister: { _ in
            calls += 1
            if calls == 1 { return try await withCheckedThrowingContinuation { oldRead = $0 } }
            return []
        }, profileLoader: { _ in throw URLError(.notConnectedToInternet) }, groupBlockWriter: { id, active, _ in
            XCTAssertEqual(id, "user-b"); XCTAssertTrue(active)
        }, groupSafetyLoader: { _ in throw URLError(.notConnectedToInternet) })
        let loading = Task { await model.load() }
        for _ in 0..<100 where oldRead == nil { await Task.yield() }
        let continuation = try XCTUnwrap(oldRead)
        // A later refresh failure does not revoke the successful block.
        try await model.setGroupBlock(userID: "user-b", active: true)
        continuation.resume(returning: [.init(id: "stale-group", name: "Old crew", created_by: "user-b", created_at: 1,
            members: [.init(group_id: "stale-group", user_id: "user-b", display_name: "Hidden member", joined_at: 1, effective_display_name: "Hidden member")])])
        await loading.value
        XCTAssertTrue(model.groups.isEmpty)
        XCTAssertTrue(model.feed.isEmpty)
        XCTAssertTrue(model.stats.isEmpty)
        XCTAssertTrue(model.activitySeries.isEmpty)
        XCTAssertEqual(model.phase, .none)
    }

    func testForegroundInvalidationClearsSecondaryGroupsBeforeNetworkAndRejectsEarlierRead() async throws {
        let suite = "GroupSafetyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(LocalPersistence(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let auth = AuthModel(tokenStore: TokenStore(), defaults: defaults)
        auth.userID = "user-a"
        let payload = try JSONSerialization.data(withJSONObject: ["sub": "user-a", "exp": 4_000_000_000])
        auth.jwt = "header." + payload.base64EncodedString().replacingOccurrences(of: "=", with: "") + ".signature"
        var oldRead: CheckedContinuation<[GroupSummary], Error>?
        var calls = 0
        let model = GroupModel(auth: auth, defaults: defaults, groupLister: { _ in
            calls += 1
            if calls == 1 { return try await withCheckedThrowingContinuation { oldRead = $0 } }
            throw URLError(.notConnectedToInternet)
        })
        let reading = Task { await model.load() }
        for _ in 0..<100 where oldRead == nil { await Task.yield() }
        let continuation = try XCTUnwrap(oldRead)
        let cached = ["selected", "secondary"].map { id in
            GroupSummary(id: id, name: "Cached crew", created_by: "user-b", created_at: 1,
                members: [.init(group_id: id, user_id: "user-b", display_name: "Hidden member",
                                joined_at: 1, effective_display_name: "Hidden member")])
        }
        model.groups = cached
        model.selectedGroupID = "selected"
        for group in cached {
            model.feed[group.id] = [.unknown(.init(id: group.id, user_id: "user-b",
                user_display_name: "Hidden member", is_me: false, date: "2026-09-10", occurred_at: 1))]
            model.stats[group.id] = [.init(user_id: "user-b", display_name: "Hidden member",
                avatar_initials: "HM", is_me: false, workout_count: 1, streak_days: 1, last_active: 1)]
            model.activitySeries[group.id] = [.init(user_id: "user-b", days: [])]
        }
        // MainTabView invokes this synchronously before awaiting Apple or network.
        model.invalidateSharedGroups()
        XCTAssertTrue(model.groups.isEmpty)
        XCTAssertTrue(model.feed.isEmpty)
        XCTAssertTrue(model.stats.isEmpty)
        XCTAssertTrue(model.activitySeries.isEmpty)
        await model.load() // Foreground fetch is unavailable; stale data stays hidden.
        continuation.resume(returning: cached)
        await reading.value
        XCTAssertTrue(model.groups.isEmpty)
        XCTAssertTrue(model.feed.isEmpty)
        if case .error = model.phase {} else { XCTFail("Expected the current offline error") }
    }


    func testRejectedBlockRevalidatesMembershipOrShowsRetryableLoadError() async throws {
        for offline in [false, true] {
            let suite = "GroupSafetyTests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(LocalPersistence(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let auth = AuthModel(tokenStore: TokenStore(), defaults: defaults)
            auth.userID = "user-a"
            let payload = try JSONSerialization.data(withJSONObject: ["sub": "user-a", "exp": 4_000_000_000])
            auth.jwt = "header." + payload.base64EncodedString().replacingOccurrences(of: "=", with: "") + ".signature"
            var reloads = 0
            let model = GroupModel(auth: auth, defaults: defaults, groupLister: { _ in
                reloads += 1
                if offline { throw URLError(.notConnectedToInternet) }
                return [] // Server confirms membership ended; only then show no groups.
            }, profileLoader: { _ in throw URLError(.notConnectedToInternet) }, groupBlockWriter: { _, _, _ in
                throw APIError.http(404, "member_unavailable")
            })
            model.phase = .ready
            model.groups = [.init(id: "old-group", name: "Old crew", created_by: "user-b", created_at: 1, members: [])]
            do {
                try await model.setGroupBlock(userID: "user-b", active: true)
                XCTFail("The rejected block must remain an error")
            } catch {
                guard case APIError.http(404, _) = error else { return XCTFail("Original block error was lost: \(error)") }
            }
            XCTAssertEqual(reloads, 1)
            XCTAssertTrue(model.groups.isEmpty)
            if offline {
                if case .error = model.phase {} else { XCTFail("Unavailable membership must offer retry") }
            } else {
                XCTAssertEqual(model.phase, .none)
            }
        }
    }


    func testLostRestrictionResponseClearsSharedDataBeforeWriteAndReconciles() async throws {
        let suite = "GroupSafetyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(LocalPersistence(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let auth = AuthModel(tokenStore: TokenStore(), defaults: defaults)
        auth.userID = "user-a"
        let payload = try JSONSerialization.data(withJSONObject: ["sub": "user-a", "exp": 4_000_000_000])
        auth.jwt = "header." + payload.base64EncodedString().replacingOccurrences(of: "=", with: "") + ".signature"
        var reloads = 0
        var model: GroupModel!
        model = GroupModel(auth: auth, defaults: defaults, groupLister: { _ in
            reloads += 1
            return []
        }, profileLoader: { _ in throw URLError(.notConnectedToInternet) }, groupRestrictionWriter: { _, _, _, _ in
            XCTAssertTrue(model.groups.isEmpty)
            XCTAssertTrue(model.feed.isEmpty)
            XCTAssertTrue(model.stats.isEmpty)
            throw URLError(.networkConnectionLost)
        })
        model.phase = .ready
        model.groups = [.init(id: "group", name: "Crew", created_by: "user-b", created_at: 1, members: [])]
        model.feed["group"] = [.unknown(.init(id: "activity", user_id: "user-b", user_display_name: "Restricted member",
            is_me: false, date: "2026-09-10", occurred_at: 1))]
        model.stats["group"] = [.init(user_id: "user-b", display_name: "Restricted member", avatar_initials: "RM",
            is_me: false, workout_count: 1, streak_days: 1, last_active: 1)]
        do {
            try await model.setSharingRestriction(userID: "user-b", active: true, reason: .harassment)
            XCTFail("The lost response must remain an error")
        } catch { XCTAssertEqual((error as? URLError)?.code, .networkConnectionLost) }
        XCTAssertEqual(reloads, 1)
        XCTAssertTrue(model.groups.isEmpty)
        XCTAssertTrue(model.feed.isEmpty)
        XCTAssertTrue(model.stats.isEmpty)
        XCTAssertEqual(model.phase, .none)
        model = nil
    }

}
