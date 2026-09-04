import SwiftUI

enum AppTab: Hashable {
    case unpack
    case pack
    case activity
    case settings
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var tab: AppTab = .unpack

    var body: some View {
        @Bindable var model = model
        Group {
            if let screen = ForcedScreen.current {
                ForcedScreenHost(screen: screen)
            } else {
                TabView(selection: $tab) {
                    UnpackView()
                        .tabItem { Label("Unpack", systemImage: "archivebox") }
                        .tag(AppTab.unpack)
                    PackView()
                        .tabItem { Label("Pack", systemImage: "plus.rectangle.on.folder") }
                        .tag(AppTab.pack)
                    ActivityView()
                        .tabItem { Label("Progress", systemImage: "clock") }
                        .tag(AppTab.activity)
                    SettingsView()
                        .tabItem { Label("Settings", systemImage: "gearshape") }
                        .tag(AppTab.settings)
                }
            }
        }
        .archiveAlerts($model.alert)
    }
}

/// Xcode 27 cannot script Simulator taps. `-ArchiveScreen <name>` opens a
/// named screen with sample data so a screenshot can be taken from simctl.
enum ForcedScreen: String {
    case unpack
    case pack
    case packAdvanced
    case settings
    case logs
    case activity
    case inspect
    case preview
    case extractSingle

    static var current: ForcedScreen? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-ArchiveScreen"),
              arguments.indices.contains(index + 1)
        else { return nil }
        return ForcedScreen(rawValue: arguments[index + 1])
    }
}

struct ForcedScreenHost: View {
    let screen: ForcedScreen
    @Environment(AppModel.self) private var model
    @State private var previewPath = "README.md"

    var body: some View {
        @Bindable var model = model
        Group {
            switch screen {
            case .unpack:
                UnpackView()
            case .pack:
                PackView()
            case .packAdvanced:
                NavigationStack {
                    PackAdvancedView(
                        sources: model.packSources,
                        name: $model.packName,
                        recipe: $model.packRecipe
                    )
                }
            case .settings:
                SettingsView()
            case .logs:
                NavigationStack { LogsView() }
            case .activity:
                ActivityView()
            case .inspect:
                NavigationStack {
                    InspectorView()
                        .navigationDestination(for: UnpackRoute.self) { route in
                            switch route {
                            case .inspect:
                                InspectorView()
                            case let .preview(path):
                                PreviewView(entryPath: path)
                            case let .extractSingle(path):
                                ExtractSingleView(entryPath: path)
                            }
                        }
                }
            case .preview:
                NavigationStack {
                    PreviewView(entryPath: previewPath)
                }
            case .extractSingle:
                NavigationStack {
                    ExtractSingleView(entryPath: previewPath)
                }
            }
        }
        .task { await seed() }
    }

    private func seed() async {
        do {
            let tree = try SampleWorkspace.makeSourceTree()
            let url = try SampleWorkspace.makeArchive()
            let entries = try ArchiveOperations.list(at: url)
            model.inspectURL = url
            model.inspectEntries = entries
            model.remember(url)
            model.packSources = [tree]
            model.packName = "Sample"
            model.packRecipe = .tarXZ
            if let file = entries.first(where: { !$0.isDirectory }) {
                previewPath = file.path
            }
            if screen == .activity {
                model.jobs.seedForPreview()
            }
            AppLog.info(.app, "opened screen \(screen.rawValue)")
        } catch {
            AppLog.error(.app, "seed failed: \(error.localizedDescription)")
        }
    }
}
