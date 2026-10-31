import Foundation
import CryptoKit

enum FS {
    static var fm: FileManager { FileManager.default }

    static func exists(_ url: URL) -> Bool { fm.fileExists(atPath: url.path) }

    static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return fm.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    static func ensure(_ url: URL) throws { try Paths.ensure(url) }

    static func read(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func readJSON(_ url: URL) -> Any? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    /// Writes through a sibling temp file then swaps, so a crash cannot leave a
    /// half-written config behind.
    @discardableResult
    static func atomicWrite(_ data: Data, to url: URL) throws -> URL {
        try ensure(url.deletingLastPathComponent())
        let tmp = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString.prefix(8)).tmp")
        try data.write(to: tmp, options: .atomic)
        if exists(url) {
            _ = try fm.replaceItemAt(url, withItemAt: tmp)
        } else {
            try fm.moveItem(at: tmp, to: url)
        }
        return url
    }

    @discardableResult
    static func atomicWrite(_ text: String, to url: URL) throws -> URL {
        try atomicWrite(Data(text.utf8), to: url)
    }

    @discardableResult
    static func backup(_ url: URL, keep: Int = 40) throws -> URL? {
        guard exists(url) else { return nil }
        try ensure(Paths.backupsDir)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime]
        let stamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
        let destination = Paths.backupsDir.appendingPathComponent("\(stamp)-\(url.lastPathComponent)")
        if exists(destination) { try? fm.removeItem(at: destination) }
        try fm.copyItem(at: url, to: destination)
        prune(keep: keep)
        return destination
    }

    private static func prune(keep: Int) {
        guard let items = try? fm.contentsOfDirectory(
            at: Paths.backupsDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let sorted = items.sorted { lhs, rhs in
            let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return left > right
        }
        for url in sorted.dropFirst(keep) { try? fm.removeItem(at: url) }
    }

    static func size(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
        if let total = values?.totalFileAllocatedSize { return Int64(total) }
        return Int64(values?.fileSize ?? 0)
    }

    static func modified(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    static func sha256(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            guard let data = try? handle.read(upToCount: 1 << 20), !data.isEmpty else { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func prettySize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func trash(_ url: URL) throws {
        try fm.trashItem(at: url, resultingItemURL: nil)
    }

    static func copyDirectory(_ source: URL, to destination: URL) throws {
        if exists(destination) { try fm.removeItem(at: destination) }
        try ensure(destination.deletingLastPathComponent())
        try fm.copyItem(at: source, to: destination)
    }

    static func children(_ url: URL, extensions: Set<String>? = nil) -> [URL] {
        guard let items = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        guard let extensions else { return items }
        return items.filter { extensions.contains($0.pathExtension.lowercased()) }
    }

    static func makeTemp(_ tag: String) throws -> URL {
        let url = fm.temporaryDirectory
            .appendingPathComponent("och-\(tag)-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func fileCount(_ url: URL) -> Int {
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey]) else { return 0 }
        var count = 0
        for case let item as URL in enumerator {
            let isFile = (try? item.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
            if isFile { count += 1 }
        }
        return count
    }

    /// Joins a relative path against a root and rejects escapes.
    static func safeJoin(_ root: URL, _ relative: String) -> URL? {
        let candidate = root.appendingPathComponent(relative).standardizedFileURL
        let rootPath = root.standardizedFileURL.path
        guard candidate.path == rootPath || candidate.path.hasPrefix(rootPath + "/") else { return nil }
        return candidate
    }
}
