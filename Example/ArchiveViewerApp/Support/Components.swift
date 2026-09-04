import SwiftUI

struct ProgressRing: View {
    var fraction: Double
    var systemImage: String
    var failed = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.18), lineWidth: 10)
            Circle()
                .trim(from: 0, to: CGFloat(clamped))
                .stroke(
                    failed ? Color.red : Color.accentColor,
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(DS.Motion.smooth, value: clamped)
            if showsPercent {
                Text(clamped, format: .percent.precision(.fractionLength(0)))
                    .font(.system(.title2, design: .rounded).monospacedDigit().weight(.semibold))
            } else {
                Image(systemName: failed ? "exclamationmark.triangle" : systemImage)
                    .font(.system(size: 36, weight: .regular))
                    .foregroundStyle(failed ? Color.red : Color.accentColor)
            }
        }
        .frame(width: 132, height: 132)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(showsPercent ? "\(Int(clamped * 100)) percent" : "Archive")
    }

    private var clamped: Double {
        min(1, max(0, fraction))
    }

    private var showsPercent: Bool {
        !failed && fraction > 0 && fraction < 1
    }
}

struct EmptyStateCard: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: DS.Padding.m) {
            Image(systemName: systemImage)
                .font(DS.Font.heroSymbol)
                .foregroundStyle(.secondary)
            Text(title)
                .font(DS.Font.title)
                .multilineTextAlignment(.center)
            Text(message)
                .font(DS.Font.detail)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(DS.Padding.xl)
    }
}

struct ArchiveEntryRow: View {
    let entry: ArchiveOperations.Entry

    var body: some View {
        HStack(spacing: DS.Padding.m) {
            Image(systemName: EntrySymbol.name(for: entry))
                .foregroundStyle(entry.isDirectory ? Color.accentColor : Color.secondary)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !parent.isEmpty {
                    Text(parent)
                        .font(DS.Font.codeCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            Spacer(minLength: DS.Padding.s)
            VStack(alignment: .trailing, spacing: 2) {
                Text(sizeText)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                if let modified = entry.modified {
                    Text(Formatters.date.string(from: modified))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var parts: [String] {
        entry.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }

    private var name: String { parts.last ?? entry.path }
    private var parent: String { parts.dropLast().joined(separator: "/") }
    private var sizeText: String {
        entry.isDirectory ? "Folder" : Formatters.bytes.string(fromByteCount: entry.size)
    }
}

struct PrimaryAction: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .clipShape(Capsule())
    }
}

struct SecondaryAction: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .clipShape(Capsule())
    }
}

struct NoteCard: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: DS.Padding.m) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(DS.Font.labelEmphasis)
                Text(message)
                    .font(DS.Font.detail)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(DS.Padding.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous))
    }
}
