import XCTest
@testable import TresFort

@MainActor
private final class FeedbackTranscriberStub: WorkoutFeedbackTranscribing {
    var handler: (() async throws -> Void)?
    var callbacks: [(@MainActor (WorkoutFeedbackTranscription) -> Void)] = []
    var stops = 0
    func start(result: @escaping @MainActor (WorkoutFeedbackTranscription) -> Void) async throws {
        callbacks.append(result)
        try await handler?()
    }
    func finish() {}
    func stop() { stops += 1 }
}

@MainActor
final class WorkoutFeedbackTests: XCTestCase {
    struct Fixture: Decodable { let recognized: String; let edited: String; let perceived_fatigue: Int }
    private func fixture() throws -> Fixture {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "WorkoutFeedback", withExtension: "json"))
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    func testVoiceEditExplicitSaveAndWireContract() async throws {
        let fixture = try fixture()
        let speech = FeedbackTranscriberStub()
        let editor = WorkoutFeedbackEditor(initial: nil, transcriber: speech)
        XCTAssertTrue(speech.callbacks.isEmpty) // opening alone never requests permission
        await editor.talk()
        speech.callbacks[0](.transcript(fixture.recognized))
        editor.finishRecording()
        XCTAssertTrue(editor.isFinalizing)
        speech.callbacks[0](.transcript(fixture.recognized + " Final words."))
        XCTAssertTrue(editor.text.hasSuffix("Final words."))
        speech.callbacks[0](.finished)
        editor.edit(fixture.edited)
        speech.callbacks[0](.transcript("late result must not win"))
        editor.fatigue = fixture.perceived_fatigue
        let approved = editor.approvedFeedback()
        XCTAssertEqual(approved.notes, fixture.edited)
        XCTAssertEqual(approved.finishBody["notes"] as? String, fixture.edited)
        XCTAssertEqual(approved.finishBody["perceived_fatigue"] as? Int, fixture.perceived_fatigue)
        XCTAssertEqual(approved.finishBody["status"] as? String, "completed")
        XCTAssertFalse(editor.isRecording)
    }

    func testPermissionDenialAndUnavailableRecognitionPreserveTypedTextAndSkipping() async {
        for error in [FeedbackRecordingError.denied, .unavailable] {
            let speech = FeedbackTranscriberStub()
            speech.handler = { throw error }
            let editor = WorkoutFeedbackEditor(initial: nil, transcriber: speech)
            editor.edit("Typed before recording")
            await editor.talk()
            XCTAssertFalse(editor.isStarting)
            XCTAssertFalse(editor.isRecording)
            XCTAssertEqual(editor.text, "Typed before recording")
            XCTAssertNotNil(editor.message)
            editor.edit("Typing still works")
            XCTAssertEqual(editor.approvedFeedback().notes, "Typing still works")
            XCTAssertNil(editor.approvedFeedback().perceivedFatigue)
        }
        let empty = WorkoutFeedbackEditor(initial: nil, transcriber: FeedbackTranscriberStub()).approvedFeedback()
        XCTAssertTrue(empty.finishBody["notes"] is NSNull)
        XCTAssertTrue(empty.finishBody["perceived_fatigue"] is NSNull)
    }

    func testCancelAndInterruptionFenceLateRecognitionWithoutErasingExistingFeedback() async {
        let speech = FeedbackTranscriberStub()
        let initial = WorkoutFeedback(notes: "Existing private note", perceivedFatigue: 6)
        let editor = WorkoutFeedbackEditor(initial: initial, transcriber: speech)
        await editor.talk()
        speech.callbacks[0](.transcript("unapproved audio words"))
        editor.cancelRecording()
        speech.callbacks[0](.transcript("late canceled result"))
        XCTAssertEqual(editor.approvedFeedback(), initial)
        await editor.talk()
        speech.callbacks[1](.transcript(""))
        editor.interrupt()
        speech.callbacks[1](.transcript("late interrupted result"))
        XCTAssertEqual(editor.approvedFeedback(), initial)
    }

    func testCancellationWhilePermissionIsPendingCannotStartOrRestoreText() async {
        let speech = FeedbackTranscriberStub()
        var permission: CheckedContinuation<Void, Never>?
        speech.handler = { await withCheckedContinuation { permission = $0 } }
        let editor = WorkoutFeedbackEditor(initial: nil, transcriber: speech)
        let pending = Task { await editor.talk() }
        while permission == nil { await Task.yield() }
        editor.cancelRecording()
        editor.edit("New typed correction")
        permission?.resume()
        await pending.value
        speech.callbacks[0](.transcript("late permission result"))
        XCTAssertEqual(editor.text, "New typed correction")
        XCTAssertFalse(editor.isRecording)
        XCTAssertFalse(editor.isStarting)
    }

    func testApprovedFeedbackSurvivesTerminalRelaunchAndMetadataCallbacks() throws {
        let fixture = try fixture()
        let feedback = WorkoutFeedback(notes: fixture.edited, perceivedFatigue: fixture.perceived_fatigue)
        let intent = WorkoutTerminalIntent(id: "finish", action: .finish, date: "2026-09-08",
            workoutID: "workout", resolvedSessionID: "session", deliveryState: .queued,
            failedHTTPStatus: nil, expectedAttempt: 4, feedback: feedback)
        var outbox = WorkoutTerminalOutbox()
        outbox.enqueue(intent)
        var restored = try JSONDecoder().decode(WorkoutTerminalOutbox.self, from: JSONEncoder().encode(outbox))
        let legacyCallback = WorkoutTerminalIntent(id: "finish", action: .finish, date: intent.date,
            workoutID: "workout", resolvedSessionID: "session", deliveryState: .failed,
            failedHTTPStatus: 422)
        restored.replace(legacyCallback)
        XCTAssertEqual(restored.intent(for: intent.date)?.feedback, feedback)
        XCTAssertEqual(restored.intent(for: intent.date)?.expectedAttempt, 4)
        XCTAssertEqual(restored.intent(for: intent.date)?.deliveryState, .failed)
        let legacy = """
        {"id":"old","action":"finish","date":"2026-09-08","deliveryState":"queued"}
        """
        XCTAssertNil(try JSONDecoder().decode(WorkoutTerminalIntent.self, from: Data(legacy.utf8)).feedback)
    }

    func testLegacySessionMissingFeedbackDecodesAndNewFeedbackRoundTrips() throws {
        let legacy = Data("{\"id\":\"s\",\"date\":\"2026-09-08\",\"status\":\"completed\"}".utf8)
        var session = try JSONDecoder().decode(SessionRow.self, from: legacy)
        XCTAssertNil(session.notes)
        XCTAssertNil(session.perceived_fatigue)
        session.notes = "My exact words"
        session.perceived_fatigue = 7
        let decoded = try JSONDecoder().decode(SessionRow.self, from: JSONEncoder().encode(session))
        XCTAssertEqual(decoded.notes, session.notes)
        XCTAssertEqual(decoded.perceived_fatigue, 7)
    }
}
