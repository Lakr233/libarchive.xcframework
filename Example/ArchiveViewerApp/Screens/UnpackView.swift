import SwiftUI

struct UnpackView: View {
    @Environment(AppModel.self) private var model
    @State private var picking = false
    @State private var listing = false
    @State private var listFraction = 0.0
    @State private var path = NavigationPath()

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: DS.Padding.l) {
                    ProgressRing(
                        fraction: listing ? listFraction : 0,
                        systemImage: "archivebox"
                    )
                    .padding(.top, DS.Padding.xl)

                    Text("Read what is inside, then extract all of it or just one file.")
                        .font(DS.Font.detail)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DS.Padding.xl)

                    VStack(spacing: DS.Padding.s) {
                        PrimaryAction(title: "Choose Archive", systemImage: "folder.badge.plus") {
                            picking = true
                        }
                        Text("The format is detected from the file itself, so any file is worth a try.")
                            .font(DS.Font.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        SecondaryAction(title: "Open Sample", systemImage: "shippingbox") {
                            openSample()
                        }
                    }
                    .padding(.horizontal, DS.Padding.l)

                    if !model.recents.isEmpty {
                        recents
                    }

                    NoteCard(
                        systemImage: "eye",
                        title: "Nothing is unpacked yet",
                        message: "The file list is read first — zip, tar, 7-Zip, rar, gzip, xz, zstd, and more. Extracting writes files into this app."
                    )
                    .padding(.horizontal, DS.Padding.l)
                    .padding(.bottom, DS.Padding.xl)
                }
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Unpack")
            .navigationBarTitleDisplayMode(.large)
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
            .sheet(isPresented: $picking) {
                DocumentPicker { urls in
                    if let url = urls.first { open(url) }
                }
                .ignoresSafeArea()
            }
            .disabled(listing)
        }
    }

    private var recents: some View {
        VStack(alignment: .leading, spacing: DS.Padding.s) {
            Text("Recent")
                .font(DS.Font.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, DS.Padding.l)
            ForEach(model.recents) { item in
                Button {
                    open(item.url)
                } label: {
                    Label(item.name, systemImage: "clock")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal, DS.Padding.l)
            }
        }
    }

    private func openSample() {
        do {
            open(try SampleWorkspace.makeArchive())
        } catch {
            model.reportFailure("Unable to Build Sample", error)
        }
    }

    private func open(_ url: URL) {
        listing = true
        listFraction = 0
        AppLog.info(.archive, "listing \(url.lastPathComponent)")
        Task.detached(priority: .userInitiated) {
            let result = Result {
                try ArchiveOperations.list(at: url) { fraction in
                    Task { @MainActor in listFraction = fraction }
                }
            }
            await MainActor.run {
                listing = false
                switch result {
                case let .success(entries):
                    model.inspectURL = url
                    model.inspectEntries = entries
                    model.remember(url)
                    path.append(UnpackRoute.inspect)
                    AppLog.info(.archive, "listed \(entries.count) entries in \(url.lastPathComponent)")
                case let .failure(error):
                    model.reportFailure("Unable to Read Archive", error)
                }
            }
        }
    }
}

enum UnpackRoute: Hashable {
    case inspect
    case preview(String)
    case extractSingle(String)
}
