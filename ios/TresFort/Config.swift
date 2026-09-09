import Foundation

enum Config {
    /// Live Cloudflare Worker (source of truth). Server, not the device,
    /// owns the data; the app is a cache + executor.
    static var apiBaseURL: URL {
#if DEBUG && targetEnvironment(simulator)
        if UIFixtureScenario.selected != nil {
            return URL(string: "https://ui-fixture.invalid")!
        }
#endif
        return URL(string: "https://tres-fort.nmarkspdx.workers.dev")!
    }
}
