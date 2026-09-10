import SwiftUI

/// The signed-in host delivers the same pending navigation after first-run
/// setup and after ordinary authentication recovery. Each sheet retains its
/// own intent and epoch, so a delayed dismissal cannot consume a newer link.
struct MemberEntryPresentation: ViewModifier {
    @ObservedObject var auth: AuthModel
    @ObservedObject var sync: SyncModel
    @ObservedObject var groupModel: GroupModel
    var onJoined: () -> Void
    var onCoach: () -> Void
    @State private var presented: MemberEntryIntent?
    @State private var presentedEpoch: UInt64?

    func body(content: Content) -> some View {
        content
            .task(id: auth.nextEntryIntent?.id) { presentNext() }
            .sheet(item: $presented, onDismiss: {
                presentedEpoch = nil
                presentNext()
            }) { intent in
                let epoch = presentedEpoch ?? auth.featureSessionEpoch
                Group {
                    switch intent.destination {
                    case let .invite(code):
                        JoinInviteConfirmSheet(groupModel: groupModel, code: code) {
                            guard auth.isCurrentFeatureSession(accountID: intent.accountID, epoch: epoch) else { return }
                            onJoined()
                        }
                    case .coach:
                        NavigationStack {
                            CoachConnectView(groupModel: groupModel)
                                .toolbar {
                                    ToolbarItem(placement: .cancellationAction) {
                                        Button("Done") { presented = nil }
                                    }
                                }
                        }
                    case .workouts:
                        WorkoutsView(sync: sync)
                    }
                }
                .onDisappear { auth.finishEntry(intent, epoch: epoch) }
            }
    }

    private func presentNext() {
        guard presented == nil, presentedEpoch == nil,
              let intent = auth.nextEntryIntent else { return }
        presentedEpoch = auth.featureSessionEpoch
        if intent.destination == .coach { onCoach() }
        presented = intent
    }
}
