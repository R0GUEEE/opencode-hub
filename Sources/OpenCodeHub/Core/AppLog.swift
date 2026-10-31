import Foundation
import Combine

enum LogLevel: String, CaseIterable, Identifiable {
    case info, success, warn, error, cli

    var id: String { rawValue }

    var label: String {
        switch self {
        case .info: return "INFO"
        case .success: return "OK"
        case .warn: return "WARN"
        case .error: return "ERROR"
        case .cli: return "CLI"
        }
    }

    var symbol: String {
        switch self {
        case .info: return "info.circle"
        case .success: return "checkmark.circle"
        case .warn: return "exclamationmark.triangle"
        case .error: return "xmark.octagon"
        case .cli: return "terminal"
        }
    }
}

struct LogEntry: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let level: LogLevel
    let text: String

    var line: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let padded = level.label.padding(toLength: 5, withPad: " ", startingAt: 0)
        return "[\(formatter.string(from: date))] \(padded) \(text)"
    }
}

/// In-memory activity feed plus an on-disk log at
/// ~/Library/Application Support/OpenCodeHub/hub.log.
@MainActor
final class AppLog: ObservableObject {
    static let shared = AppLog()

    @Published private(set) var entries: [LogEntry] = []

    private let limit = 3000
    private let fileURL = Paths.appLogFile
    private var handle: FileHandle?

    init() {
        try? Paths.ensure(Paths.appSupport)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: fileURL)
        _ = try? handle?.seekToEnd()
        if let text = FS.read(fileURL) {
            for line in text.split(separator: "\n").suffix(100) {
                entries.append(LogEntry(date: Date(), level: .info, text: String(line)))
            }
        }
    }

    func write(_ level: LogLevel, _ text: String) {
        let entry = LogEntry(date: Date(), level: level, text: text)
        entries.append(entry)
        if entries.count > limit { entries.removeFirst(entries.count - limit) }
        if let data = (entry.line + "\n").data(using: .utf8) {
            try? handle?.write(contentsOf: data)
        }
    }

    func info(_ text: String) { write(.info, text) }
    func success(_ text: String) { write(.success, text) }
    func warn(_ text: String) { write(.warn, text) }
    func error(_ text: String) { write(.error, text) }
    func cli(_ text: String) { write(.cli, text) }

    func record(_ result: ShellResult) {
        let summary = "\(result.command) -> \(result.status) in \(String(format: "%.1fs", result.duration))"
        write(result.succeeded ? .success : .error, summary)
        let body = result.output
        if !body.isEmpty { write(.cli, body.count > 4000 ? String(body.suffix(4000)) : body) }
    }

    func clear() {
        entries.removeAll()
        try? handle?.close()
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        handle = try? FileHandle(forWritingTo: fileURL)
    }

    func exportText() -> String { entries.map(\.line).joined(separator: "\n") }
}
