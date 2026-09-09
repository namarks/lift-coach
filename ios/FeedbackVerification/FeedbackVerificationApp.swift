import SwiftUI

/// A separate local-only device check. This target links only the production
/// feedback editor and on-device transcriber: no API, auth, cache, or account.
@main
struct FeedbackVerificationApp: App {
    var body: some Scene { WindowGroup { FeedbackVerificationView() } }
}

private struct FeedbackVerificationView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var editor = WorkoutFeedbackEditor(initial: nil, transcriber: OnDeviceFeedbackTranscriber())
    @State private var saved: String?
    @FocusState private var typing: Bool
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("LOCAL VERIFICATION").font(.headline)
                    Text("No account access. No network API. Saved text stays in this screen's memory; recordings are discarded.")
                }
                Section {
                    if editor.isStarting {
                        Text("Waiting for permission")
                        Button("Cancel recording") { editor.cancelRecording() }
                    } else if editor.isRecording {
                        Button("Stop recording") { editor.finishRecording() }
                        Button("Cancel recording") { editor.cancelRecording() }
                    } else if editor.isFinalizing {
                        Text("Finishing transcription…")
                        Button("Use current text") { editor.stop() }
                    } else {
                        Button("Talk about your workout") { Task { await editor.talk() } }
                    }
                    Button("Type instead") { editor.stop(); typing = true }
                    if let message = editor.message { Text(message) }
                }
                Section("Review and edit") {
                    TextEditor(text: Binding(get: { editor.text }, set: { editor.edit($0) }))
                        .frame(minHeight: 140).focused($typing)
                    Button("Save feedback") { saved = editor.approvedFeedback().notes; typing = false }
                        .disabled(editor.isStarting || editor.isRecording)
                    Button("Skip") { editor.stop(); typing = false; saved = "Skipped without feedback" }
                }
                if let saved { Section("Saved locally for this check") { Text(verbatim: saved) } }
            }
            .navigationTitle("Feedback Check")
            .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { typing = false } } }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .background { editor.interrupt() } }
        .onDisappear { editor.stop() }
    }
}
