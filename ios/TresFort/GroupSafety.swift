import Foundation

struct GroupSafetyState: Decodable {
    let blocks: [BlockedGroupMember]
    let restriction: SharingRestriction?
    let can_moderate: Bool
}

struct BlockedGroupMember: Decodable, Identifiable {
    var id: String { user_id }
    let user_id: String
    let created_at: Int
}

struct SharingRestriction: Decodable {
    let active: Int
    let reason: String
    let updated_at: Int
}

enum GroupReportReason: String, CaseIterable, Identifiable {
    case harassment, hate, sexual_content, threats, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .harassment: return "Harassment"
        case .hate: return "Hateful content"
        case .sexual_content: return "Sexual content"
        case .threats: return "Threats"
        case .other: return "Other"
        }
    }
}

struct GroupReport: Identifiable {
    let groupID: String
    let memberID: String
    var itemID: String? = nil
    var itemType: String? = nil
    var id: String { reference }
    static let supportEmail = "nick@tresfort.app"

    // IDs only: never automatically include names, notes, health data or codes.
    var reference: String {
        var text = "Group: \(groupID)\nMember: \(memberID)"
        if let itemID { text += "\nItem: \(itemType ?? "activity") / \(itemID)" }
        return text
    }

    func emailURL(reason: GroupReportReason) -> URL? {
        var url = URLComponents()
        url.scheme = "mailto"
        url.path = Self.supportEmail
        url.queryItems = [
            URLQueryItem(name: "subject", value: "Très Fort group report"),
            URLQueryItem(name: "body", value: "Category: \(reason.label)\n\(reference)\n\nPlease describe the concern before sending:\n")
        ]
        return url.url
    }
}

extension APIClient {
    func getGroupSafety(jwt: String) async throws -> GroupSafetyState {
        try await get("api/me/group-safety", jwt: jwt)
    }

    func setGroupBlock(userID: String, active: Bool, jwt: String) async throws {
        let _: EmptyResponse = try await put("api/me/group-blocks/\(userID)", body: ["active": active], jwt: jwt)
    }

    func setSharingRestriction(userID: String, active: Bool, reason: GroupReportReason, jwt: String) async throws {
        let _: EmptyResponse = try await put("api/group-safety/restrictions/\(userID)",
            body: ["active": active, "reason": reason.rawValue], jwt: jwt)
    }
}

extension FeedItem {
    var reportType: String {
        switch self {
        case .session: return "session"
        case .ride: return "ride"
        case .activity: return "activity"
        case .unknown: return "unknown"
        }
    }
}
