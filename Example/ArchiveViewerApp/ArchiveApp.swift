import SwiftUI

@main
struct ArchiveApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .interfaceTextSize()
                .tint(Color.accentColor)
                .task { AppLog.start() }
        }
    }
}
