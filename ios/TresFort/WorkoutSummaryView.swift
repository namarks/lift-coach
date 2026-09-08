import SwiftUI

struct WorkoutSummaryView: View {
    @ObservedObject var sync: SyncModel
    let sessionID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let summary = sync.completionSummary(for: sessionID) {
                Text("\(summary.working_sets) WORKING SETS · \(summary.total_reps) REPS")
                    .font(Theme.mono(12, .bold)).foregroundStyle(Theme.text)
                if let volume = summary.external_load_volume {
                    Text("\(SetValueFormatter.number(volume)) lb external-load volume")
                        .font(Theme.mono(11)).foregroundStyle(Theme.muted)
                }
                ForEach(summary.cohorts) { cohort in
                    Text("\(cohort.name) · \(cohort.label)").font(Theme.mono(11)).foregroundStyle(Theme.muted)
                }
                if !summary.records.isEmpty {
                    Text("PERSONAL RECORDS").font(Theme.mono(11, .bold)).foregroundStyle(Theme.accent)
                    ForEach(summary.records) { record in
                        Text("\(record.name) · \(record.label) · previous \(record.previous)\(record.metric == "duration" ? "s" : " reps")")
                            .font(.subheadline).foregroundStyle(Theme.text)
                    }
                }
                if summary.targets_available {
                    let differences = summary.targets.filter(\.differs)
                    if !differences.isEmpty {
                        Text("CHANGES FROM STARTING TARGETS").font(Theme.mono(11, .bold)).foregroundStyle(Theme.muted)
                        ForEach(differences) { target in
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(target.name) · \(target.actual_sets)/\(target.sets) sets")
                                if target.missed_sets > 0 { Text("\(target.missed_sets) sets not logged") }
                                if target.changed_sets > 0 { Text("\(target.changed_sets) sets with a different load, reps, duration or RPE") }
                                if target.below_target_sets > 0 { Text("\(target.below_target_sets) below the rep or duration target") }
                            }.font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                    if summary.targets.contains(where: { $0.comparison_available == false }) {
                        Text("Some starting targets can no longer be matched to their original slots.")
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                } else {
                    Text("Starting targets were not recorded for this session.").font(.caption).foregroundStyle(Theme.muted)
                }
            } else {
                Text("Workout saved. \(sync.summaryErrors[sessionID] ?? "Loading completion summary…")")
                    .font(.subheadline).foregroundStyle(Theme.muted)
                if sync.summaryErrors[sessionID] != nil {
                    Button("Retry summary") { Task { await sync.loadCompletionSummary(sessionID: sessionID) } }
                        .frame(minHeight: 44)
                }
            }
        }
        .task(id: "\(sessionID):\(sync.summaryRevision)") {
            await sync.loadCompletionSummary(sessionID: sessionID)
        }
    }
}
