import SwiftUI

/// One correction surface is used by both the active slot and final review.
/// Original server values remain visible until the correction is acknowledged.
struct SetReviewList: View {
    @ObservedObject var sync: SyncModel
    let sets: [SetLog]
    let pending: [PendingSetIntent]
    @State private var editing: ReviewItem?

    private struct ReviewItem: Identifiable {
        let set: SetLog?
        let pending: PendingSetIntent?
        var id: String { self.set?.id ?? pending!.id }
        var exerciseID: String { self.set?.exercise_id ?? pending!.body.exercise_id }
        var values: SetCorrectionValues {
            SetCorrectionValues(weight: set?.weight ?? pending!.body.weight,
                                reps: set?.reps ?? pending!.body.reps,
                                rpe: set != nil ? set!.rpe : pending!.body.rpe,
                                durationSeconds: set != nil ? set!.duration_s : pending!.body.duration_s)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(sets) { set in row(ReviewItem(set: set, pending: nil)) }
            ForEach(pending) { intent in row(ReviewItem(set: nil, pending: intent)) }
            if sync.correctionRefreshNeeded {
                Text("Correction saved. Refresh needed.").font(.caption).foregroundStyle(Theme.muted)
            }
        }
        .sheet(item: $editing) { item in
            SetValuesEditor(
                title: "Correct set", values: item.values,
                timed: item.set.map { sync.isTimedSet($0) } ?? item.pending!.body.is_timed,
                allowsAssistance: sync.isBodyweightExercise(item.exerciseID)
                    || sync.isTimedExercise(item.exerciseID),
                onSave: { values in
                    if let set = item.set { return sync.enqueueCorrection(set: set, values: values) }
                    return sync.enqueueCorrection(pending: item.pending!, values: values)
                }, onDelete: {
                    if let set = item.set { return sync.enqueueCorrection(set: set, values: nil) }
                    return sync.enqueueCorrection(pending: item.pending!, values: nil)
                })
        }
    }

    private func row(_ item: ReviewItem) -> some View {
        let correction = sync.correction(for: item.id)
        let timed = item.set.map { sync.isTimedSet($0) } ?? item.pending!.body.is_timed
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(sync.exerciseName(item.exerciseID)).font(Theme.mono(11))
                    Text(SetValueFormatter.value(
                        weight: item.values.weight, reps: item.values.reps,
                        durationSeconds: item.values.durationSeconds, timed: timed,
                        bodyweight: sync.isBodyweightExercise(item.exerciseID)))
                        .font(Theme.mono(14, .bold))
                    if let rpe = item.values.rpe { Text("RPE \(SetValueFormatter.number(rpe))").font(.caption) }
                    if (item.set?.is_warmup == 1) || item.pending?.body.is_warmup == true {
                        Text("Warm-up").font(.caption).foregroundStyle(Theme.muted)
                    }
                }
                Spacer()
                Button("Edit") { editing = item }
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(correction != nil || sync.hasPendingTerminalIntentForCurrentWorkout)
            }
            if let correction {
                let failed = correction.deliveryState == .failed
                Text(failed
                     ? (correction.failedHTTPStatus == 409
                        ? "Correction needs review: this set or workout changed."
                        : "\(correction.isDelete ? "Delete" : "Edit") rejected (HTTP \(correction.failedHTTPStatus ?? 400)).")
                     : "\(correction.isDelete ? "Delete" : "Edit") pending — original retained until saved.")
                    .font(.caption).foregroundStyle(failed ? Theme.danger : Theme.muted)
                if let values = correction.values {
                    Text("Requested: " + SetValueFormatter.value(
                        weight: values.weight, reps: values.reps, durationSeconds: values.durationSeconds,
                        timed: timed, bodyweight: sync.isBodyweightExercise(item.exerciseID)))
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                if failed {
                    HStack {
                        Button("Retry") { Task { await sync.retryCorrection(id: correction.id) } }
                        Spacer()
                        Button("Reload to review") { Task { await sync.dismissRejectedCorrection(id: correction.id) } }
                    }.font(.caption).frame(minHeight: 44)
                }
            }
            if let pending = item.pending {
                HStack {
                    Text(pending.deliveryState == .failed ? "Set not saved" : "Set queued on this device")
                        .font(.caption).foregroundStyle(Theme.muted)
                    Spacer()
                    if pending.deliveryState == .failed {
                        Button("Retry set") { Task { await sync.retrySetIntent(id: pending.id) } }
                    }
                }
            }
        }
        .foregroundStyle(Theme.text)
        .padding(12).background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct SetValuesEditor: View {
    let title: String
    let timed: Bool
    let allowsAssistance: Bool
    let onSave: (SetCorrectionValues) -> Bool
    let onDelete: (() -> Bool)?
    @Environment(\.dismiss) private var dismiss
    @State private var weight: String
    @State private var reps: String
    @State private var rpe: String
    @State private var duration: String
    @State private var error: String?

    init(title: String, values: SetCorrectionValues, timed: Bool, allowsAssistance: Bool,
         onSave: @escaping (SetCorrectionValues) -> Bool, onDelete: (() -> Bool)? = nil) {
        self.title = title; self.timed = timed; self.allowsAssistance = allowsAssistance
        self.onSave = onSave; self.onDelete = onDelete
        _weight = State(initialValue: SetValueFormatter.number(values.weight))
        _reps = State(initialValue: String(values.reps))
        _rpe = State(initialValue: values.rpe.map(SetValueFormatter.number) ?? "")
        _duration = State(initialValue: String(values.durationSeconds ?? (timed ? values.reps : 30)))
    }

    private var values: SetCorrectionValues? {
        guard let weight = Double(weight), weight.isFinite, allowsAssistance || weight >= 0,
              let reps = Int(reps), reps >= 0,
              rpe.isEmpty || Double(rpe).map({ $0.isFinite && (0...10).contains($0) }) == true,
              !timed || Int(duration).map({ $0 > 0 }) == true else { return nil }
        return SetCorrectionValues(weight: weight, reps: timed ? (Int(duration) ?? 0) : reps,
                                   rpe: Double(rpe), durationSeconds: timed ? Int(duration) : nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                LabeledContent(allowsAssistance ? "Load / assist (lb)" : "Weight (lb)") {
                    TextField("Weight", text: $weight).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing)
                }
                LabeledContent(timed ? "Duration (seconds)" : "Reps") {
                    TextField(timed ? "Seconds" : "Reps", text: timed ? $duration : $reps)
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                }
                LabeledContent("RPE (optional)") {
                    TextField("—", text: $rpe).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
                if allowsAssistance { Text("Use a negative load for assistance, 0 for bodyweight, or a positive added load.").font(.caption) }
                if let error { Text(error).foregroundStyle(.red) }
                if let onDelete {
                    Button("Delete set", role: .destructive) {
                        if onDelete() { dismiss() } else { error = "Workout changed. Close this sheet and review the set again." }
                    }
                }
            }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let values, onSave(values) { dismiss() }
                        else { error = "Workout changed. Close this sheet and review the values again." }
                    }.disabled(values == nil)
                }
            }
        }
    }
}

/// Recovery must expose corrections even before the runner is resumed.
struct PendingCorrectionsView: View {
    @ObservedObject var sync: SyncModel
    var body: some View {
        DisclosureGroup("\(sync.setCorrections.count) set correction\(sync.setCorrections.count == 1 ? "" : "s") waiting to sync") {
            ForEach(sync.setCorrections) { intent in
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(sync.exerciseName(intent.exerciseID)) · \(intent.isDelete ? "delete" : "edit") · \(intent.deliveryState == .failed ? "needs review" : "pending")")
                    HStack {
                        Button("Retry") { Task { await sync.retryCorrection(id: intent.id) } }
                            .disabled(sync.sendingCorrectionIDs.contains(intent.id))
                        if intent.deliveryState == .failed {
                            Spacer()
                            Button("Reload to review") { Task { await sync.dismissRejectedCorrection(id: intent.id) } }
                        }
                    }.frame(minHeight: 44)
                }.padding(.top, 8)
            }
        }
        .font(Theme.mono(11)).foregroundStyle(Theme.accent)
        .padding(14).background(Theme.surface)
    }
}
