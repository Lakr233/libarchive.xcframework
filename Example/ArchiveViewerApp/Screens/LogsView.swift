import SwiftUI
import UIKit

/// Settings ▸ Logs: one row per journal entry, newest at the bottom. The
/// ⋯ menu picks a launch, filters by level, refreshes, shares the file,
/// and trims older launches. Reads are `LogReader`'s; nothing here writes.
struct LogsView: View {
    @State private var model = LogViewerModel()
    @State private var window: UIWindow?
    @State private var revealed = false

    var body: some View {
        content
            .navigationTitle("Logs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    menu
                }
            }
            .background(WindowReader(window: $window))
            .onAppear(perform: model.loadOnce)
    }

    @ViewBuilder
    private var content: some View {
        let entries = model.visibleEntries
        if entries.isEmpty {
            emptyState
        } else {
            VStack(spacing: 0) {
                header(count: entries.count)
                ScrollViewReader { proxy in
                    List {
                        ForEach(entries) { entry in
                            LogEntryRow(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .listStyle(.plain)
                    .opacity(revealed ? 1 : 0)
                    .onAppear { scrollToEnd(proxy) }
                    .onChange(of: model.document.readAt) { _, _ in
                        scrollToEnd(proxy)
                    }
                }
            }
        }
    }

    private func header(count: Int) -> some View {
        HStack(spacing: DS.Padding.s) {
            Image(systemName: "doc.text")
            Text(verbatim: model.fileName)
            Text("\(count.formatted()) entries")
                .foregroundStyle(Color.secondary.opacity(0.7))
            Spacer()
        }
        .font(DS.Font.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, DS.Padding.l)
        .padding(.vertical, DS.Padding.s)
        .background(Color(.secondarySystemGroupedBackground))
    }

    private var emptyState: some View {
        VStack(spacing: DS.Padding.m) {
            if model.isLoading {
                ProgressView()
            } else {
                Image(systemName: model.document.unreadable ? "doc.text.magnifyingglass" : "doc.text")
                    .font(DS.Font.heroSymbol)
                    .foregroundStyle(.secondary)
                if model.document.unreadable {
                    Text("Unable to read the log file. Refresh to try again.")
                        .font(DS.Font.body)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No log entries. Refresh to check again.")
                        .font(DS.Font.body)
                        .foregroundStyle(.secondary)
                }
                Text(verbatim: model.document.location)
                    .font(DS.Font.codeCaption)
                    .foregroundStyle(Color.secondary.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DS.Padding.xl)
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        guard let last = model.visibleEntries.last else {
            revealed = true
            return
        }
        DispatchQueue.main.async {
            proxy.scrollTo(last.id, anchor: .bottom)
            DispatchQueue.main.async {
                withAnimation(DS.Motion.smooth) {
                    revealed = true
                }
            }
        }
    }

    private var menu: some View {
        Menu {
            if !model.olderLaunches.isEmpty {
                Menu {
                    Picker("Launch", selection: $model.launch) {
                        Text("Current Launch")
                            .tag(URL?.none)
                        ForEach(model.olderLaunches) { launch in
                            Text(verbatim: model.title(of: launch))
                                .tag(Optional(launch.url))
                        }
                    }
                } label: {
                    Label("Launch", systemImage: "clock")
                }
            }
            Menu {
                ForEach(LogEntry.Level.allCases, id: \.self) { level in
                    Toggle(isOn: model.binding(for: level)) {
                        Text(level.title)
                    }
                }
            } label: {
                Label("Level", systemImage: "slider.horizontal.3")
            }
            if !model.document.categories.isEmpty {
                Menu {
                    Toggle(isOn: model.allCategoriesBinding) {
                        Text("All Categories")
                    }
                    Divider()
                    ForEach(model.document.categories, id: \.self) { category in
                        Toggle(isOn: model.binding(for: category)) {
                            Text(verbatim: category)
                        }
                    }
                } label: {
                    Label("Category", systemImage: "tag")
                }
            }
            Divider()
            Button(action: model.reload) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            Button(action: share) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            if !model.olderLaunches.isEmpty {
                Divider()
                Button(role: .destructive, action: model.deleteOlderLaunches) {
                    Label("Delete Older Logs", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    private func share() {
        guard let url = LogReader.exportFile(launch: model.launch) else { return }
        ShareSheet.present(url, in: window)
    }
}

private struct LogEntryRow: View {
    let entry: LogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Padding.xs) {
            Text(verbatim: entry.message)
                .font(DS.Font.code)
                .foregroundStyle(messageColor)
            HStack(spacing: DS.Padding.xs) {
                if !entry.timestamp.isEmpty {
                    Text(verbatim: entry.timestamp)
                    Text(verbatim: "·")
                }
                Text(verbatim: entry.category)
                if entry.level != .info {
                    Text(verbatim: "·")
                    Text(entry.level.title)
                }
            }
            .font(DS.Font.codeCaption)
            .foregroundStyle(metaColor)
        }
        .padding(.vertical, DS.Padding.xs)
        .listRowBackground(rowBackground)
        .contextMenu {
            Button {
                UIPasteboard.general.string = entry.text
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            Button {
                UIPasteboard.general.string = entry.message
            } label: {
                Label("Copy Message", systemImage: "text.quote")
            }
        }
    }

    private var messageColor: Color {
        switch entry.level {
        case .verbose: .secondary
        case .info: .primary
        case .warning: .orange
        case .error: .red
        }
    }

    private var metaColor: Color {
        switch entry.level {
        case .warning: Color.orange.opacity(0.8)
        case .error: Color.red.opacity(0.8)
        default: Color.secondary.opacity(0.7)
        }
    }

    private var rowBackground: Color? {
        switch entry.level {
        case .warning: Color.orange.opacity(0.06)
        case .error: Color.red.opacity(0.06)
        default: nil
        }
    }
}

extension LogEntry.Level {
    var title: LocalizedStringKey {
        switch self {
        case .verbose: "Verbose"
        case .info: "Info"
        case .warning: "Warning"
        case .error: "Error"
        }
    }
}

@Observable
@MainActor
final class LogViewerModel {
    var launch: URL? {
        didSet { if launch != oldValue { reload() } }
    }

    var levels: Set<LogEntry.Level> = Set(LogEntry.Level.allCases)
    var categories: Set<String> = []
    private(set) var document = LogDocument()
    private(set) var launches: [LogLaunch] = []
    private(set) var isLoading = false
    private var hasLoaded = false

    var olderLaunches: [LogLaunch] {
        let current = AppLog.currentFile?.standardizedFileURL
        return launches.filter { $0.url.standardizedFileURL != current }
    }

    var fileName: String {
        (document.location as NSString).lastPathComponent
    }

    var visibleEntries: [LogEntry] {
        document.entries.filter { entry in
            levels.contains(entry.level)
                && (categories.isEmpty || categories.contains(entry.category))
        }
    }

    func loadOnce() {
        guard !hasLoaded else { return }
        hasLoaded = true
        reload()
    }

    func reload() {
        let launch = launch
        isLoading = true
        Task.detached(priority: .userInitiated) {
            let launches = LogReader.launches()
            let document = LogReader.read(launch: launch)
            await MainActor.run { [weak self] in
                guard let self, self.launch == launch else { return }
                self.launches = launches
                self.document = document
                self.isLoading = false
            }
        }
    }

    func deleteOlderLaunches() {
        LogReader.deleteOlderLaunches()
        if launch != nil {
            launch = nil
        } else {
            reload()
        }
    }

    func title(of launch: LogLaunch) -> String {
        guard let date = launch.date else { return launch.url.lastPathComponent }
        return Self.launchTitleFormatter.string(from: date)
    }

    private static let launchTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    func binding(for level: LogEntry.Level) -> Binding<Bool> {
        Binding(
            get: { self.levels.contains(level) },
            set: { on in
                if on { self.levels.insert(level) } else { self.levels.remove(level) }
            }
        )
    }

    func binding(for category: String) -> Binding<Bool> {
        Binding(
            get: { self.categories.contains(category) },
            set: { on in
                if on { self.categories.insert(category) } else { self.categories.remove(category) }
            }
        )
    }

    var allCategoriesBinding: Binding<Bool> {
        Binding(
            get: { self.categories.isEmpty },
            set: { on in if on { self.categories = [] } }
        )
    }
}
