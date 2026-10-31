import SwiftUI

@MainActor
struct LogsView: View {
    @EnvironmentObject private var workspace: Workspace
    @EnvironmentObject private var log: AppLog
    @State private var level: LogLevel?
    @State private var query = ""

    private var entries: [LogEntry] {
        log.entries.filter { entry in
            if let level, entry.level != level { return false }
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return true }
            return entry.text.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Picker("Level", selection: $level) {
                    Text("All").tag(LogLevel?.none)
                    ForEach(LogLevel.allCases) { level in
                        Text(level.label).tag(LogLevel?.some(level))
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 420)

                TextField("Filter", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)

                Spacer()

                Button {
                    workspace.copyToPasteboard(log.exportText())
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                Button {
                    log.clear()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                Button {
                    workspace.reveal(Paths.appLogFile)
                } label: {
                    Label("Log file", systemImage: "folder")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(entries) { entry in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: entry.level.symbol)
                                    .font(.caption2)
                                    .foregroundStyle(color(for: entry.level))
                                    .frame(width: 14)
                                Text(entry.text)
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .textSelection(.enabled)
                                    .foregroundStyle(entry.level == .cli ? Color.secondary : Color.primary)
                            }
                            .id(entry.id)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: log.entries.count) { _ in
                    if let last = entries.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private func color(for level: LogLevel) -> Color {
        switch level {
        case .info: return .secondary
        case .success: return .green
        case .warn: return .orange
        case .error: return .red
        case .cli: return .gray
        }
    }
}
