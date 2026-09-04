import Foundation
import SwiftUI

struct RecentItem: Identifiable, Hashable {
    let id: UUID
    let name: String
    let url: URL
}

@Observable
@MainActor
final class AppModel {
    let jobs = JobCenter()
    var recents: [RecentItem] = []
    var alert: AlertRequest?
    var skipHidden = true
    var defaultRecipe: ArchiveOperations.Recipe = .zip
    var inspectURL: URL?
    var inspectEntries: [ArchiveOperations.Entry] = []
    var packSources: [URL] = []
    var packName = "Archive"
    var packRecipe: ArchiveOperations.Recipe = .zip

    func remember(_ url: URL) {
        recents.removeAll { $0.url == url }
        recents.insert(RecentItem(id: UUID(), name: url.lastPathComponent, url: url), at: 0)
        if recents.count > 12 {
            recents = Array(recents.prefix(12))
        }
    }

    func confirm(
        _ title: String.LocalizationValue,
        message: String.LocalizationValue,
        confirm: String.LocalizationValue,
        kind: AlertButtonStyle.Kind = .accent,
        action: @escaping () -> Void
    ) {
        alert = AlertRequest(
            title: title,
            message: message,
            actions: [
                ("Cancel", .normal, {}),
                (confirm, kind, action),
            ]
        )
    }

    func reportFailure(_ title: String.LocalizationValue, _ error: Error) {
        AppLog.error(.app, error.localizedDescription)
        alert = AlertRequest(
            title: title,
            message: "\(error.localizedDescription)",
            actions: [("OK", .accent, {})]
        )
    }
}
