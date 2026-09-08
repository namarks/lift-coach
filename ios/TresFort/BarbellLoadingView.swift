import SwiftUI

struct BarbellLoadingView: View {
    let target: Double
    @State private var bar = 45.0
    @State private var steps: [WarmupStep] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Plates") {
                    LabeledContent("Chosen load", value: "\(SetValueFormatter.number(target)) lb")
                    LabeledContent("Bar (lb)") {
                        TextField("Bar", value: $bar, format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    if let result = BarbellLoading.breakdown(target: target, bar: bar) {
                        if result.perSide.isEmpty { Text("Empty bar") }
                        else {
                            Text("Each side").font(.headline)
                            ForEach(result.perSide) { plate in
                                LabeledContent("\(SetValueFormatter.number(plate.weight)) lb", value: "× \(plate.count)")
                            }
                        }
                        if result.remainingWeight > 0 {
                            Text("These plates make \(SetValueFormatter.number(result.achievableWeight)) lb; \(SetValueFormatter.number(result.remainingWeight)) lb remains.")
                                .foregroundStyle(.secondary)
                        }
                        Text("Uses 45, 35, 25, 10, 5 and 2.5 lb plates.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Choose a positive bar weight at or below the target.").foregroundStyle(.secondary)
                    }
                }
                Section {
                    ForEach($steps) { $step in
                        HStack {
                            TextField("Load", value: $step.weight, format: .number).keyboardType(.decimalPad)
                            Text("lb ×")
                            TextField("Reps", value: $step.reps, format: .number).keyboardType(.numberPad)
                            Text("reps")
                        }
                    }
                    Button("Reset ramp for this load") { reset() }
                } header: {
                    Text("Warm-up guide")
                } footer: {
                    Text("Adjust the steps to suit your session. This loading guide does not log sets.")
                }
            }
            .navigationTitle("Barbell loading").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { reset() }
        }
    }

    private func reset() { steps = BarbellLoading.warmup(target: target, bar: bar) }
}
