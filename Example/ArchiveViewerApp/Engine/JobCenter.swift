import Foundation

struct ArchiveJob: Identifiable, Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case extract
        case extractOne
        case create
    }

    enum Status: Equatable, Sendable {
        case running
        case succeeded
        case failed
    }

    let id: UUID
    var kind: Kind
    var title: String
    var detail: String
    var fraction: Double
    var status: Status
    var errorText: String?
}

/// Owns in-flight and finished archive jobs. Mutations hop to the main actor;
/// the work itself runs off it so listing a large zip does not stall the UI.
@Observable
@MainActor
final class JobCenter {
    private(set) var jobs: [ArchiveJob] = []

    var current: ArchiveJob? {
        jobs.first { $0.status == .running }
    }

    var isBusy: Bool {
        current != nil
    }

    var others: [ArchiveJob] {
        jobs.filter { $0.id != current?.id }
    }

    func extract(archive: URL, to directory: URL, title: String) {
        enqueue(kind: .extract, title: title, detail: archive.lastPathComponent) { report in
            try ArchiveOperations.extract(archive: archive, to: directory) { fraction, path in
                report(fraction, path)
            }
            return directory
        }
    }

    func extractOne(archive: URL, entry: String, to file: URL) {
        enqueue(kind: .extractOne, title: file.lastPathComponent, detail: entry) { report in
            try ArchiveOperations.extract(archive: archive, entry: entry, to: file) { fraction in
                report(fraction, entry)
            }
            return file
        }
    }

    func create(sources: [URL], to destination: URL, recipe: ArchiveOperations.Recipe) {
        enqueue(
            kind: .create,
            title: destination.lastPathComponent,
            detail: recipe.pathExtension
        ) { report in
            try ArchiveOperations.create(
                sources: sources,
                to: destination,
                recipe: recipe
            ) { fraction, path in
                report(fraction, path)
            }
            return destination
        }
    }

    private func enqueue(
        kind: ArchiveJob.Kind,
        title: String,
        detail: String,
        work: @escaping @Sendable (
            @escaping @Sendable (Double, String) -> Void
        ) throws -> URL
    ) {
        let id = UUID()
        jobs.insert(
            ArchiveJob(
                id: id,
                kind: kind,
                title: title,
                detail: detail,
                fraction: 0,
                status: .running,
                errorText: nil
            ),
            at: 0
        )
        AppLog.info(.job, "started \(kind.rawValue) “\(title)”")
        Task.detached(priority: .userInitiated) {
            do {
                let result = try work { fraction, path in
                    Task { @MainActor in
                        self.patch(id) {
                            $0.fraction = fraction
                            if !path.isEmpty { $0.detail = path }
                        }
                    }
                }
                await MainActor.run {
                    self.patch(id) {
                        $0.fraction = 1
                        $0.status = .succeeded
                        $0.detail = result.lastPathComponent
                    }
                    AppLog.info(.job, "finished \(kind.rawValue) “\(title)”")
                }
            } catch {
                await MainActor.run {
                    self.patch(id) {
                        $0.status = .failed
                        $0.errorText = error.localizedDescription
                    }
                    AppLog.error(.job, "failed \(kind.rawValue) “\(title)”: \(error.localizedDescription)")
                }
            }
        }
    }

    private func patch(_ id: UUID, _ body: (inout ArchiveJob) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        body(&jobs[index])
    }

    /// Fills the Progress tab for a screenshot. Not used by the live job path.
    func seedForPreview() {
        jobs = [
            ArchiveJob(
                id: UUID(),
                kind: .extract,
                title: "Sample.tar.xz",
                detail: "src/main.c",
                fraction: 0.62,
                status: .running,
                errorText: nil
            ),
            ArchiveJob(
                id: UUID(),
                kind: .create,
                title: "Notes.zip",
                detail: "Notes.zip",
                fraction: 1,
                status: .succeeded,
                errorText: nil
            ),
        ]
    }
}
