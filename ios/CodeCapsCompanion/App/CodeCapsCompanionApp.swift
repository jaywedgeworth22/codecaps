import SwiftUI

/// App entry point for the CodeCaps iOS companion application.
@main
struct CodeCapsCompanionApp: App {
    @StateObject private var model = CompanionQuotaModel()

    var body: some Scene {
        WindowGroup {
            CompanionContentView(model: model)
        }
    }
}
