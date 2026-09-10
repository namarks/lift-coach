import SwiftUI

struct GroupMemberSafetyActions: View {
    let report: GroupReport
    @ObservedObject var model: GroupModel
    var canBlock = true
    @State private var showReport = false
    @State private var confirmBlock = false
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        Menu {
            Button("Report", systemImage: "flag") { showReport = true }
            if canBlock {
                Button("Block member", systemImage: "person.crop.circle.badge.xmark", role: .destructive) {
                    confirmBlock = true
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("Group safety options")
        .disabled(busy)
        .sheet(isPresented: $showReport) {
            GroupReportSheet(report: report, model: model, canBlock: canBlock)
        }
        .confirmationDialog("Block this member?", isPresented: $confirmBlock, titleVisibility: .visible) {
            Button("Block member", role: .destructive) {
                busy = true
                Task {
                    do { try await model.setGroupBlock(userID: report.memberID, active: true) }
                    catch { self.error = error.localizedDescription }
                    busy = false
                }
            }
        } message: {
            Text("You’ll stop seeing each other’s profiles and activity in all shared groups. They won’t be notified. You can unblock them in Profile → Group safety. Previously viewed or copied information may remain.")
        }
        .alert("Couldn’t update block", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
    }
}

struct GroupReportSheet: View {
    let report: GroupReport
    @ObservedObject var model: GroupModel
    let canBlock: Bool
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var reason: GroupReportReason = .harassment
    @State private var message: String?
    @State private var confirmBlock = false
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Reason", selection: $reason) {
                        ForEach(GroupReportReason.allCases) { Text($0.label).tag($0) }
                    }
                    Button("Draft report email") {
                        guard let url = report.emailURL(reason: reason) else { return }
                        openURL(url) { opened in
                            if !opened { message = "Mail couldn’t open. Copy the reference and email it to the support address below." }
                        }
                    }
                } footer: {
                    Text("Review the email and describe the concern before sending. Only reference IDs are filled in; workout details, names and invite codes are not attached. Reports are checked daily, with actionable abuse addressed within 24 hours.")
                }
                Section("If Mail is unavailable") {
                    Text(GroupReport.supportEmail).textSelection(.enabled)
                    Button("Copy report reference") {
                        UIPasteboard.general.string = "Category: \(reason.label)\n\(report.reference)"
                        message = "Reference copied. Include it in your email to support."
                    }
                }
                if canBlock {
                    Section {
                        Button("Block member", role: .destructive) { confirmBlock = true }
                            .disabled(busy)
                    } footer: {
                        Text("Blocking hides your profiles and activity from one another in all shared groups. It doesn’t send a report.")
                    }
                }
                if let message { Section { Text(message).font(.footnote) } }
            }
            .navigationTitle("Report a concern")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Block this member?", isPresented: $confirmBlock, titleVisibility: .visible) {
                Button("Block member", role: .destructive) {
                    busy = true
                    Task {
                        do {
                            try await model.setGroupBlock(userID: report.memberID, active: true)
                            message = "Member blocked. You can unblock them in Profile → Group safety."
                        } catch { message = error.localizedDescription }
                        busy = false
                    }
                }
            }
        }
    }
}

struct GroupSafetyView: View {
    @ObservedObject var model: GroupModel
    @State private var busy = false
    @State private var message: String?
    @State private var unblock: BlockedGroupMember?
    @State private var memberID = ""
    @State private var reason: GroupReportReason = .harassment
    @State private var restrict = true
    @State private var confirmRestriction = false

    var body: some View {
        Form {
            if let safety = model.groupSafety {
                if safety.restriction?.active == 1 {
                    Section { Text("Your group sharing is restricted. Contact support for help. Your private training records remain available.") }
                }
                Section("Blocked members") {
                    if safety.blocks.isEmpty { Text("No blocked members").foregroundStyle(.secondary) }
                    ForEach(safety.blocks) { member in
                        HStack {
                            Text("Member …\(member.user_id.suffix(6))")
                            Spacer()
                            Button("Unblock") { unblock = member }.disabled(busy)
                        }
                    }
                }
                if safety.can_moderate {
                    Section("Operator: group sharing") {
                        TextField("Member ID from report", text: $memberID)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        Picker("Reason", selection: $reason) {
                            ForEach(GroupReportReason.allCases) { Text($0.label).tag($0) }
                        }
                        Button("Restrict sharing", role: .destructive) { restrict = true; confirmRestriction = true }
                            .disabled(busy || UUID(uuidString: memberID.trimmingCharacters(in: .whitespacesAndNewlines)) == nil)
                        Button("Restore sharing") { restrict = false; confirmRestriction = true }
                            .disabled(busy || UUID(uuidString: memberID.trimmingCharacters(in: .whitespacesAndNewlines)) == nil)
                    }
                }
            } else {
                Section { Text("Group safety settings are unavailable.") }
            }
            Section {
                Button("Refresh") { Task { await refresh() } }.disabled(busy)
                Link("Contact support", destination: AppInformation.supportURL)
                if let message { Text(message).font(.footnote) }
            }
        }
        .navigationTitle("Group safety")
        .task { await refresh() }
        .confirmationDialog("Unblock this member?", isPresented: Binding(get: { unblock != nil }, set: { if !$0 { unblock = nil } }), titleVisibility: .visible) {
            Button("Unblock") {
                guard let member = unblock else { return }
                busy = true
                Task {
                    do { try await model.setGroupBlock(userID: member.user_id, active: false) }
                    catch { message = error.localizedDescription }
                    unblock = nil
                    busy = false
                }
            }
        } message: { Text("You may see each other’s shared activity again unless they have also blocked you.") }
        .confirmationDialog(restrict ? "Restrict this account’s group sharing?" : "Restore this account’s group sharing?", isPresented: $confirmRestriction, titleVisibility: .visible) {
            Button(restrict ? "Restrict sharing" : "Restore sharing", role: restrict ? .destructive : nil) {
                busy = true
                Task {
                    do {
                        try await model.setSharingRestriction(userID: memberID.trimmingCharacters(in: .whitespacesAndNewlines), active: restrict, reason: reason)
                        message = restrict ? "Group sharing restricted." : "Group sharing restored."
                    } catch { message = error.localizedDescription }
                    busy = false
                }
            }
        } message: { Text("This changes group sharing only. The action and reason are recorded. Private training records stay available.") }
    }

    private func refresh() async {
        do { try await model.refreshGroupSafety(); message = nil }
        catch { message = error.localizedDescription }
    }
}
