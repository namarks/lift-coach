import SwiftUI

@main
struct TresFortApp: App {
    @StateObject private var model: AuthModel

    init() {
#if DEBUG && targetEnvironment(simulator)
        if UIFixtureScenario.selected != nil {
            _model = StateObject(wrappedValue: UIFixtureModel.makeAuth())
            return
        }
#endif
        _model = StateObject(wrappedValue: AuthModel())
    }

    var body: some Scene {
        WindowGroup {
#if DEBUG && targetEnvironment(simulator)
            if let scenario = UIFixtureScenario.selected {
                UIFixtureView(auth: model, scenario: scenario)
            } else {
                RootView().environmentObject(model)
            }
#else
            RootView().environmentObject(model)
#endif
        }
    }
}
