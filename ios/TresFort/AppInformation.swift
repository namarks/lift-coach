import SwiftUI

enum AppInformation {
    static let privacyURL = URL(string: "https://tresfort.app/privacy")!
    static let supportURL = URL(string: "mailto:nick@tresfort.app")!
    static let anthropicPrivacyURL = URL(string: "https://www.anthropic.com/legal/privacy")!
}

struct PrivacyPolicyLink: View {
    var body: some View {
        Link(destination: AppInformation.privacyURL) {
            Text("Privacy policy").frame(minHeight: 44)
        }
        .accessibilityIdentifier("app.privacy-policy")
    }
}
