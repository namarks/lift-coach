#if DEBUG && targetEnvironment(simulator)
import Foundation
import SwiftUI

/// Explicit, simulator-only launch fixtures. Release/device builds contain none
/// of this code. An unknown fixture fails closed before constructing real auth.
enum UIFixtureScenario: String, CaseIterable {
    case signIn = "sign-in", empty, loadFailure = "load-failure"
    case ordinary, bodyweight, timed, pending, onboarding, groups, library
    case historySmall = "history-small", historyLarge = "history-large"

    var isHistory: Bool { self == .historySmall || self == .historyLarge }
    case correctionFailure = "correction-failure", readyToFinish = "ready-to-finish"

    static let selected: Self? = {
        guard let raw = ProcessInfo.processInfo.environment["TRESFORT_UI_FIXTURE"] else { return nil }
        guard let value = Self(rawValue: raw) else { fatalError("Unknown synthetic UI fixture") }
        return value
    }()
}

private final class FixtureTokenStore: AppTokenStore {
    func load() -> String? { nil }
    func save(_ token: String) {}
    func clear() {}
}

@MainActor
enum UIFixtureModel {
    // One synthetic namespace; reset before every launch. Never load Keychain
    // or the standard defaults used by an installed user's account.
    static let defaults: UserDefaults = {
        let name = "com.nmarkspdx.tresfort.synthetic-ui"
        let value = UserDefaults(suiteName: name)!
        if !(UIFixtureScenario.selected?.isHistory == true && ProcessInfo.processInfo.environment["TRESFORT_UI_REUSE_HISTORY"] == "1") {
            value.removePersistentDomain(forName: name)
        }
        return value
    }()
    static func makeAuth() -> AuthModel {
        let auth = AuthModel(tokenStore: FixtureTokenStore(), defaults: defaults)
        if UIFixtureScenario.selected != .signIn {
            auth.userID = "synthetic-ui-user"
            auth.jwt = "synthetic-ui-bearer"
            auth.onboardingComplete = UIFixtureScenario.selected != .onboarding
            auth.phase = .signedIn
        }
        if let scenario = UIFixtureScenario.selected, scenario.isHistory,
           ProcessInfo.processInfo.environment["TRESFORT_UI_REUSE_HISTORY"] != "1" {
            let history = HistoryFixtureData.dataset(sessionCount: scenario == .historySmall ? 12 : 1_040)
            let state = StateResponse(plan: PlanTree(id: "synthetic-plan", name: "Synthetic history", version: 1, workouts: [], meta: nil),
                plan_version: 1, sessions: history.sessions, sets: history.sets,
                external_events: [], external_activities: [], activities: [], server_time: history.server_time)
            StateSnapshotStore.save(state, userID: auth.userID, defaults: defaults)
            let catalog = (0..<40).map { ExerciseCatalog(id: "exercise-\($0)", name: "Exercise \($0)",
                primary_muscle: "legs", modality: "barbell", unit: "lb", laterality: nil, load_mode: nil, demo_slug: nil) }
            ExerciseCatalogSnapshotStore.save(catalog, userID: auth.userID, defaults: defaults)
            _ = StateSyncAccountStore.activate(userID: auth.userID, defaults: defaults)

        }
        return auth
    }
}

struct UIFixtureView: View {
    @Environment(\.dynamicTypeSize) private var systemDynamicTypeSize
    @ObservedObject var auth: AuthModel
    let scenario: UIFixtureScenario
    @StateObject private var sync: SyncModel

    init(auth: AuthModel, scenario: UIFixtureScenario) {
        self.auth = auth
        self.scenario = scenario
        _sync = StateObject(wrappedValue: SyncModel(
            auth: auth, defaults: UIFixtureModel.defaults,
            now: { CalendarProjection.date(from: "2026-09-08")! },
            restActivityUpdater: { _, _ in }, restActivityEnder: {},
            restNotificationCanceller: {}))
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("SYNTHETIC · \(scenario.rawValue)")
                .font(.caption).dynamicTypeSize(.large)
                .accessibilityIdentifier("fixture.scenario")
                .accessibilityValue(Text(verbatim: scenario.isHistory ? "\(sync.sets.count) sets" : ""))
            if scenario == .signIn {
                RootView().environmentObject(auth)
            } else if scenario == .onboarding && !auth.onboardingComplete {
                OnboardingView(auth: auth)
            } else if scenario.isHistory {
                HistoryView(sync: sync)
            } else {
                TodayView(sync: sync, auth: auth)
            }
        }
        .tint(Theme.accent)
        .environment(\.openURL, OpenURLAction { _ in .discarded })
        .environment(\.dynamicTypeSize,
            ProcessInfo.processInfo.environment["TRESFORT_UI_LARGE_TEXT"] == "1" ? .accessibility5 : systemDynamicTypeSize)
        .task {
            guard scenario != .signIn, !scenario.isHistory else { return }
            await sync.load()
            if ![.empty, .loadFailure, .onboarding, .groups].contains(scenario) {
                sync.startWorkout()
                if [.readyToFinish, .correctionFailure].contains(scenario) {
                    sync.finished = true
                }
                if scenario == .pending, let exercise = sync.currentExercise {
                    await sync.logCurrentSet(expected: exercise, expectedSetNumber: sync.currentPhysicalSetNumber)
                    sync.skipRest()
                }
            }
        }
    }
}

/// This ephemeral URLSession has exactly one protocol. Every request is either
/// answered from memory or rejected; no request is forwarded to a network.
final class UIFixtureProtocol: URLProtocol {
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [UIFixtureProtocol.self]
        return URLSession(configuration: config)
    }()
    private static let lock = NSLock()
    private static var server = UIFixtureServer(scenario: UIFixtureScenario.selected ?? .empty)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let result = Result { try Self.server.respond(request) }
        Self.lock.unlock()
        do {
            let (status, data) = try result.get()
            let response = HTTPURLResponse(url: request.url!, statusCode: status,
                httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

/// A bounded transport fixture, not a second implementation of the backend.
/// Stateful responses exist only for the creation/log/correction/finish smoke.
private struct UIFixtureServer {
    let scenario: UIFixtureScenario
    var plan: [String: Any]?
    var sessions: [[String: Any]] = []
    var sets: [[String: Any]] = []
    var groupReceipts: [String: [String: Any]] = [:]
    var revision = 1_788_912_000_000
    let dayID = "synthetic-day", sessionID = "synthetic-session"

    init(scenario: UIFixtureScenario) {
        self.scenario = scenario
        if ![.signIn, .empty, .loadFailure, .onboarding].contains(scenario) {
            plan = makePlan()
            sessions = [.groups, .library].contains(scenario) ? [] : [makeSession()]
            if [.readyToFinish, .correctionFailure].contains(scenario) {
                sets = [["id": "synthetic-set", "session_id": sessionID,
                    "exercise_id": "synthetic-exercise", "template_exercise_id": "synthetic-slot",
                    "set_index": 1, "weight": 45, "reps": 5, "is_warmup": 0,
                    "logged_at": revision, "updated_at": revision, "is_timed": 0]]
            }
        }
    }

    // The same contract is consumed by real-D1 and unit tests. Only the UI
    // test bundle carries the file; the app receives it via launch environment.
    var groupFixture: [String: Any] {
        guard let raw = ProcessInfo.processInfo.environment["TRESFORT_UI_GROUP_CONTRACT"],
              let data = raw.data(using: .utf8),
              let fixture = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            preconditionFailure("Missing synthetic group contract")
        }
        return fixture
    }

    func makeSession(status: String = "in_progress", attempt: Int = 1) -> [String: Any] {
        ["id": sessionID, "date": "2026-09-08", "status": status,
         "workout_id": dayID, "updated_at": revision,
         "attempt": attempt, "write_protocol": "attempt-v1"]
    }
    func makePlan(name: String = "Synthetic Training", workouts: Bool = true) -> [String: Any] {
        if scenario == .library {
            return ["id": "synthetic-plan", "name": "My Workouts", "version": 1,
                "meta": "{\"schedule\":{\"version\":1,\"week\":{\"tue\":\"synthetic-day\"}}}",
                "days": [["id": dayID, "name": "Gym", "order_index": 0, "exercises": []],
                         ["id": "hotel", "name": "Hotel", "order_index": 1, "exercises": []]]]
        }
        if scenario == .groups {
            return ["id": "synthetic-plan", "name": groupFixture["name"]!, "version": 1,
                "meta": "{\"schedule\":{\"version\":1,\"week\":{\"tue\":\"synthetic-day\"}}}",
                "days": [["id": dayID, "name": groupFixture["day_name"]!, "order_index": 0,
                          "exercises": groupFixture["slots"]!]]]
        }
        let modality = scenario == .bodyweight ? "bw" : scenario == .timed ? "timed" : "barbell"
        var slot: [String: Any] = ["id": "synthetic-slot", "exercise_id": "synthetic-exercise",
            "exercise_name": scenario == .bodyweight ? "Pull-Up" : scenario == .timed ? "Plank" : "Barbell Squat",
            "exercise_unit": "lb", "exercise_modality": modality, "order_index": 0,
            "target_sets": 1, "target_reps": 5, "rest_seconds": 0,
            "target_weight": modality == "barbell" ? 45 : 0]
        if scenario == .timed { slot["target_duration_s"] = 5 }
        let meta = "{\"schedule\":{\"version\":1,\"week\":{\"tue\":\"synthetic-day\"}}}"
        return ["id": "synthetic-plan", "name": name, "version": 1, "meta": meta,
            "days": workouts ? [["id": dayID, "name": "Workout A", "order_index": 0,
                              "exercises": [slot]]] : []]
    }

    mutating func respond(_ request: URLRequest) throws -> (Int, Data) {
        guard request.url?.host == "ui-fixture.invalid" else { throw URLError(.unsupportedURL) }
        guard !scenario.isHistory else { throw URLError(.notConnectedToInternet) }
        let path = request.url!.path
        let method = request.httpMethod ?? "GET"
        var data = request.httpBody
        if data == nil, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 4096)
            var body = Data()
            while stream.hasBytesAvailable {
                let count = stream.read(&bytes, maxLength: bytes.count)
                if count < 0 { throw URLError(.cannotDecodeContentData) }
                if count == 0 { break }
                body.append(contentsOf: bytes.prefix(count))
            }
            data = body
        }
        let body = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        revision += 1
        var response: Any
        var status = 200
        switch (method, path) {
        case ("GET", "/api/state"):
            if scenario == .loadFailure { throw URLError(.notConnectedToInternet) }
            if scenario == .groups {
                guard request.value(forHTTPHeaderField: "X-TresFort-Capabilities")?
                    .split(separator: ",").contains(where: { $0.trimmingCharacters(in: .whitespaces) == "groups" }) == true
                else { throw URLError(.badServerResponse) }
            }
            response = ["plan": plan as Any? ?? NSNull(), "plan_version": plan?["version"] ?? 0,
                "sessions": sessions, "sets": sets, "server_time": revision, "plan_groups_version": 1,
                "activities": [], "external_events": [], "external_activities": []]
        case ("GET", "/api/exercises") where scenario == .groups:
            response = (groupFixture["slots"] as! [[String: Any]]).map { slot in
                ["id": slot["exercise_id"]!, "name": slot["exercise_name"]!,
                 "modality": slot["exercise_modality"]!, "unit": "lb", "primary_muscle": "full body"]
            }
        case ("GET", "/api/exercises"):
            response = [["id": "synthetic-exercise",
                "name": scenario == .bodyweight ? "Pull-Up" : scenario == .timed ? "Plank" : "Barbell Squat",
                "modality": scenario == .bodyweight ? "bw" : scenario == .timed ? "timed" : "barbell",
                "unit": "lb", "primary_muscle": "legs"]]
        case ("PUT", "/api/plan/active"):
            plan = makePlan(name: body["name"] as? String ?? "My Training", workouts: false)
            response = ["plan": ["id": "synthetic-plan", "name": plan!["name"]!, "version": 1], "created": true]
        case ("PUT", "/api/plan/schedule") where scenario == .library:
            let version = (plan?["version"] as? Int ?? 1) + 1
            let schedule: [String: Any] = ["version": 1, "week": body["week"] ?? [:]]
            plan?["meta"] = String(data: try JSONSerialization.data(withJSONObject: ["schedule": schedule]), encoding: .utf8)
            plan?["version"] = version
            response = ["ok": true, "version": version, "schedule": schedule]
        case ("PUT", "/api/calendar/2026-09-08") where scenario == .library:
            let row: [String: Any] = ["id": sessionID, "date": "2026-09-08", "status": "planned",
                "day_template_id": body["day_template_id"] ?? NSNull(), "attempt": 1, "updated_at": revision]
            sessions = [row]
            response = ["ok": true, "session": row]
        case ("DELETE", "/api/days/hotel") where scenario == .library:
            let remaining = (plan?["days"] as? [[String: Any]] ?? []).filter { $0["id"] as? String != "hotel" }
            let version = (plan?["version"] as? Int ?? 1) + 1
            plan?["days"] = remaining
            plan?["version"] = version
            response = ["ok": true, "version": plan?["version"] ?? 1]
        case ("POST", "/api/days"):
            var day: [String: Any] = ["id": dayID, "name": body["name"] ?? "Workout A",
                                      "order_index": 0, "exercises": []]
            day["label"] = NSNull()
            plan?["days"] = [day]; plan?["version"] = 2
            response = ["id": dayID]
        case ("PUT", "/api/days/\(dayID)/groups") where scenario == .groups:
            let receiptKey = String(data: try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]), encoding: .utf8)!
            if let receipt = groupReceipts[receiptKey] { response = receipt; break }
            guard let version = plan?["version"] as? Int, body["expected_version"] as? Int == version else {
                status = 409; response = ["conflict": true, "current_version": plan?["version"] ?? 0]; break
            }
            guard let groupID = body["group_id"] as? String, UUID(uuidString: groupID) != nil,
                  let ids = body["exercises"] as? [String] else { throw URLError(.badServerResponse) }
            var days = plan!["days"] as! [[String: Any]]
            var slots = days[0]["exercises"] as! [[String: Any]]
            if !ids.isEmpty {
                // Only the two prescribed selections in this journey are accepted.
                let expected = (groupFixture["groups"] as! [[String: Any]]).first { group in
                    let indices = group["member_indices"] as! [Int]
                    let original = groupFixture["slots"] as! [[String: Any]]
                    return indices.map { original[$0]["id"] as! String } == ids
                }
                guard let expected,
                      body["round_rest"] as? Int == expected["round_rest"] as? Int,
                      body["transition_rest"] as? Int == expected["transition_rest"] as? Int,
                      body["target_sets"] as? Int == expected["rounds"] as? Int else {
                    throw URLError(.badServerResponse)
                }
            }
            for index in slots.indices where ids.contains(slots[index]["id"] as! String)
                || (ids.isEmpty && slots[index]["group_id"] as? String == groupID) {
                slots[index]["group_id"] = ids.isEmpty ? NSNull() : groupID as Any
                slots[index]["group_rest_seconds"] = ids.isEmpty ? NSNull() : body["round_rest"]!
                slots[index]["group_transition_seconds"] = ids.isEmpty ? NSNull() : body["transition_rest"]!
                if !ids.isEmpty { slots[index]["target_sets"] = body["target_sets"]! }
            }
            days[0]["exercises"] = slots; plan?["days"] = days; plan?["version"] = version + 1
            let ack: [String: Any] = ["ok": true, "plan_id": "synthetic-plan", "version": version + 1,
                "group_id": groupID, "day_id": dayID, "members": ids,
                "round_rest": body["round_rest"] ?? NSNull(), "transition_rest": body["transition_rest"] ?? NSNull(),
                "target_sets": body["target_sets"] ?? NSNull(), "cleared": ids.isEmpty]
            groupReceipts[receiptKey] = ack
            response = ack
        case ("POST", "/api/sessions"):
            if sessions.isEmpty {
                guard body["expected_attempt"] as? Int == 0 else { throw URLError(.badServerResponse) }
                sessions = [makeSession(attempt: 0)]
            }
            response = sessions[0]
        case ("POST", "/api/sessions/\(sessionID)/sets"):
            if scenario == .pending { throw URLError(.notConnectedToInternet) }
            if scenario == .groups, !sets.contains(where: { $0["id"] as? String == body["id"] as? String }) {
                let indices = groupFixture["execution_indices"] as! [Int]
                let slots = groupFixture["slots"] as! [[String: Any]]
                guard sets.count < indices.count,
                      body["template_exercise_id"] as? String == slots[indices[sets.count]]["id"] as? String else {
                    // A wrong member is observable as a failed set; never bless a
                    // sequential runner just because it eventually logs eight sets.
                    status = 422; response = ["error": "Synthetic member sequence mismatch"]; break
                }
            }
            var set = body
            set["is_warmup"] = (body["is_warmup"] as? Bool == true) ? 1 : 0
            set["is_timed"] = (body["is_timed"] as? Bool == true) ? 1 : 0
            set["session_id"] = sessionID; set["updated_at"] = revision
            set["logged_at"] = revision
            sets.removeAll { ($0["id"] as? String) == (set["id"] as? String) }
            sets.append(set)
            sessions = [makeSession(attempt: sessions.first?["attempt"] as? Int ?? 0)]
            response = ["set": set, "session": sessions[0], "deduped": false]
        case ("PATCH", "/api/sets/synthetic-set"):
            status = 422; response = ["error": "Synthetic correction rejected"]
        case ("PATCH", "/api/sessions/\(sessionID)"):
            sessions = [makeSession(status: "completed", attempt: sessions.first?["attempt"] as? Int ?? 0)]
            response = sessions[0]
        case ("GET", "/api/sessions/\(sessionID)/summary"):
            let workingSets = sets.filter { $0["is_warmup"] as? Int == 0 }
            let totalReps = workingSets.reduce(0) { $0 + ($1["reps"] as? Int ?? 0) }
            let externalVolume = workingSets.reduce(0.0) {
                $0 + ($1["weight"] as? Double ?? 0) * Double($1["reps"] as? Int ?? 0)
            }
            response = ["version": 1, "session_id": sessionID, "date": "2026-09-08", "attempt": sessions.first?["attempt"] ?? 0,
                "final": sessions.first?["status"] as? String == "completed", "working_sets": workingSets.count,
                "total_reps": totalReps, "external_load_volume": externalVolume,
                "cohorts": [], "records": [], "targets_available": false, "targets": []]
        default:
            // Unsupported UI interactions are visible failures, never passthrough.
            status = 501; response = ["error": "No synthetic response for \(method) \(path)"]
        }
        return (status, try JSONSerialization.data(withJSONObject: response, options: [.sortedKeys]))
    }
}
#endif
