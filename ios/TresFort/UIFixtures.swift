#if DEBUG && targetEnvironment(simulator)
import Foundation
import SwiftUI

/// Explicit, simulator-only launch fixtures. Release/device builds contain none
/// of this code. An unknown fixture fails closed before constructing real auth.
enum UIFixtureScenario: String, CaseIterable {
    case signIn = "sign-in", empty, loadFailure = "load-failure"
    case ordinary, bodyweight, timed, pending
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
        value.removePersistentDomain(forName: name)
        return value
    }()
    static func makeAuth() -> AuthModel {
        let auth = AuthModel(tokenStore: FixtureTokenStore(), defaults: defaults)
        if UIFixtureScenario.selected != .signIn {
            auth.userID = "synthetic-ui-user"
            auth.jwt = "synthetic-ui-bearer"
            auth.onboardingComplete = true
            auth.phase = .signedIn
        }
        return auth
    }
}

struct UIFixtureView: View {
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
                .font(.caption).accessibilityIdentifier("fixture.scenario")
            if scenario == .signIn {
                RootView().environmentObject(auth)
            } else {
                TodayView(sync: sync, auth: auth)
            }
        }
        .task {
            guard scenario != .signIn else { return }
            await sync.load()
            if ![.empty, .loadFailure].contains(scenario) {
                sync.startWorkout()
                if [.readyToFinish, .correctionFailure].contains(scenario) {
                    sync.finished = true
                }
                if scenario == .pending, let exercise = sync.currentExercise {
                    await sync.logCurrentSet(expected: exercise, expectedSetNumber: sync.currentSetNumber)
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
    var revision = 1_788_912_000_000
    let dayID = "synthetic-day", sessionID = "synthetic-session"

    init(scenario: UIFixtureScenario) {
        self.scenario = scenario
        if ![.signIn, .empty, .loadFailure].contains(scenario) {
            plan = makePlan()
            sessions = [makeSession()]
            if [.readyToFinish, .correctionFailure].contains(scenario) {
                sets = [["id": "synthetic-set", "session_id": sessionID,
                    "exercise_id": "synthetic-exercise", "template_exercise_id": "synthetic-slot",
                    "set_index": 1, "weight": 45, "reps": 5, "is_warmup": 0,
                    "logged_at": revision, "updated_at": revision, "is_timed": 0]]
            }
        }
    }

    func makeSession(status: String = "in_progress") -> [String: Any] {
        ["id": sessionID, "date": "2026-09-08", "status": status,
         "day_template_id": dayID, "updated_at": revision,
         "attempt": 1, "write_protocol": "attempt-v1"]
    }
    func makePlan(name: String = "Synthetic Training", days: Bool = true) -> [String: Any] {
        let modality = scenario == .bodyweight ? "bw" : scenario == .timed ? "timed" : "barbell"
        var slot: [String: Any] = ["id": "synthetic-slot", "exercise_id": "synthetic-exercise",
            "exercise_name": scenario == .bodyweight ? "Pull-Up" : scenario == .timed ? "Plank" : "Barbell Squat",
            "exercise_unit": "lb", "exercise_modality": modality, "order_index": 0,
            "target_sets": 1, "target_reps": 5, "rest_seconds": 0,
            "target_weight": modality == "barbell" ? 45 : 0]
        if scenario == .timed { slot["target_duration_s"] = 5 }
        let meta = "{\"schedule\":{\"version\":1,\"week\":{\"tue\":\"synthetic-day\"}}}"
        return ["id": "synthetic-plan", "name": name, "version": 1, "meta": meta,
            "days": days ? [["id": dayID, "name": "Workout A", "order_index": 0,
                              "exercises": [slot]]] : []]
    }

    mutating func respond(_ request: URLRequest) throws -> (Int, Data) {
        guard request.url?.host == "ui-fixture.invalid" else { throw URLError(.unsupportedURL) }
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
            response = ["plan": plan as Any? ?? NSNull(), "plan_version": plan?["version"] ?? 0,
                "sessions": sessions, "sets": sets, "server_time": revision,
                "activities": [], "external_events": [], "external_activities": []]
        case ("GET", "/api/exercises"):
            response = [["id": "synthetic-exercise",
                "name": scenario == .bodyweight ? "Pull-Up" : scenario == .timed ? "Plank" : "Barbell Squat",
                "modality": scenario == .bodyweight ? "bw" : scenario == .timed ? "timed" : "barbell",
                "unit": "lb", "primary_muscle": "legs"]]
        case ("PUT", "/api/plan/active"):
            plan = makePlan(name: body["name"] as? String ?? "My Training", days: false)
            response = ["plan": ["id": "synthetic-plan", "name": plan!["name"]!, "version": 1], "created": true]
        case ("POST", "/api/days"):
            var day: [String: Any] = ["id": dayID, "name": body["name"] ?? "Workout A",
                                      "order_index": 0, "exercises": []]
            day["label"] = NSNull()
            plan?["days"] = [day]; plan?["version"] = 2
            response = ["id": dayID]
        case ("POST", "/api/sessions"):
            if sessions.isEmpty { sessions = [makeSession()] }
            response = sessions[0]
        case ("POST", "/api/sessions/\(sessionID)/sets"):
            if scenario == .pending { throw URLError(.notConnectedToInternet) }
            var set = body
            set["is_warmup"] = (body["is_warmup"] as? Bool == true) ? 1 : 0
            set["is_timed"] = (body["is_timed"] as? Bool == true) ? 1 : 0
            set["session_id"] = sessionID; set["updated_at"] = revision
            set["logged_at"] = revision
            sets.removeAll { ($0["id"] as? String) == (set["id"] as? String) }
            sets.append(set)
            sessions = [makeSession()]
            response = ["set": set, "session": sessions[0], "deduped": false]
        case ("PATCH", "/api/sets/synthetic-set"):
            status = 422; response = ["error": "Synthetic correction rejected"]
        case ("PATCH", "/api/sessions/\(sessionID)"):
            sessions = [makeSession(status: "completed")]
            response = sessions[0]
        case ("GET", "/api/sessions/\(sessionID)/summary"):
            response = ["version": 1, "session_id": sessionID, "date": "2026-09-08", "attempt": 1,
                "final": sessions.first?["status"] as? String == "completed", "working_sets": sets.count,
                "total_reps": sets.count * 5, "external_load_volume": sets.count * 225,
                "cohorts": [], "records": [], "targets_available": false, "targets": []]
        default:
            // Unsupported UI interactions are visible failures, never passthrough.
            status = 501; response = ["error": "No synthetic response for \(method) \(path)"]
        }
        return (status, try JSONSerialization.data(withJSONObject: response, options: [.sortedKeys]))
    }
}
#endif
