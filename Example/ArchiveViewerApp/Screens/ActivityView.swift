import SwiftUI

struct ActivityView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Group {
                if model.jobs.jobs.isEmpty {
                    EmptyStateCard(
                        systemImage: "clock",
                        title: "No Activity",
                        message: "Extract and pack jobs show their progress here."
                    )
                } else {
                    List {
                        if let current = model.jobs.current, current.status == .running {
                            Section("In Progress") {
                                jobCard(current)
                            }
                        }
                        if !model.jobs.others.isEmpty {
                            Section("Jobs") {
                                ForEach(model.jobs.others) { job in
                                    jobRow(job)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Progress")
        }
    }

    private func jobCard(_ job: ArchiveJob) -> some View {
        VStack(spacing: DS.Padding.m) {
            ProgressRing(
                fraction: job.fraction,
                systemImage: job.kind == .create ? "plus.rectangle.on.folder" : "square.and.arrow.down",
                failed: false
            )
            Text(job.title)
                .font(DS.Font.title)
                .multilineTextAlignment(.center)
            Text(job.detail)
                .font(DS.Font.codeCaption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Padding.l)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func jobRow(_ job: ArchiveJob) -> some View {
        HStack(spacing: DS.Padding.m) {
            Image(systemName: symbol(for: job))
                .foregroundStyle(color(for: job))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(job.title)
                    .lineLimit(1)
                Text(job.errorText ?? job.detail)
                    .font(DS.Font.caption)
                    .foregroundStyle(job.status == .failed ? .red : .secondary)
                    .lineLimit(2)
            }
            Spacer()
            if job.status == .running {
                Text(job.fraction, format: .percent.precision(.fractionLength(0)))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func symbol(for job: ArchiveJob) -> String {
        switch job.status {
        case .running: "arrow.triangle.2.circlepath"
        case .succeeded: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private func color(for job: ArchiveJob) -> Color {
        switch job.status {
        case .running: .accentColor
        case .succeeded: .green
        case .failed: .red
        }
    }
}
