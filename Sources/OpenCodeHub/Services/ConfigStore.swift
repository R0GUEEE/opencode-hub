import Foundation
import Combine

/// Owns ~/.config/opencode/opencode.json. The document is kept untyped so keys
/// this app does not understand survive a round trip untouched.
@MainActor
final class ConfigStore: ObservableObject {
    @Published private(set) var root: [String: Any] = [:]
    @Published private(set) var fileExists = false
    @Published private(set) var lastLoadedAt: Date?
    @Published private(set) var loadError: String?

    let url: URL

    init(url: URL = Paths.configFile) {
        self.url = url
        reload()
    }

    func reload() {
        loadError = nil
        fileExists = FS.exists(url)
        guard fileExists else {
            root = [:]
            lastLoadedAt = Date()
            return
        }
        do {
            let data = try Data(contentsOf: url)
            root = try JSONC.object(from: data)
            lastLoadedAt = Date()
        } catch {
            loadError = "opencode.json could not be parsed: \(error.localizedDescription)"
            root = [:]
        }
    }

    /// Applies a mutation, writes it, and refreshes published state.
    func mutate(_ body: (inout [String: Any]) throws -> Void) throws {
        if let loadError {
            throw HubError.invalidInput("\(loadError) Fix the file before using the hub to edit it.")
        }
        var next = root
        try body(&next)
        if next.isEmpty { next["$schema"] = "https://opencode.ai/config.json" }
        let data = try JSONC.data(next)
        _ = try FS.backup(url)
        try FS.atomicWrite(data, to: url)
        root = next
        fileExists = true
        lastLoadedAt = Date()
    }

    func ensureFileExists() throws {
        guard !fileExists else { return }
        let template: [String: Any] = ["$schema": "https://opencode.ai/config.json"]
        try FS.ensure(url.deletingLastPathComponent())
        try FS.atomicWrite(try JSONC.data(template), to: url)
        root = template
        fileExists = true
        lastLoadedAt = Date()
    }

    // MARK: - Plugins

    var pluginSpecs: [String] { JSONC.stringArray(root["plugin"]) }

    func setPluginSpecs(_ specs: [String]) throws {
        let normalized = ConfigStore.normalizeSpecs(specs)
        try mutate { root in
            if normalized.isEmpty {
                root.removeValue(forKey: "plugin")
            } else {
                root["plugin"] = normalized
            }
        }
    }

    func addPluginSpec(_ spec: String) throws {
        let trimmed = spec.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw HubError.invalidInput("Enter an npm package name.") }
        var specs = pluginSpecs.filter { NpmPlugin(spec: $0).name != NpmPlugin(spec: trimmed).name }
        specs.append(trimmed)
        try setPluginSpecs(specs)
    }

    func removePluginSpec(named name: String) throws {
        try setPluginSpecs(pluginSpecs.filter { NpmPlugin(spec: $0).name != name })
    }

    func setPluginVersion(name: String, version: String?) throws {
        let spec = version.map { "\(name)@\($0)" } ?? name
        var specs = pluginSpecs
        if let index = specs.firstIndex(where: { NpmPlugin(spec: $0).name == name }) {
            specs[index] = spec
        } else {
            specs.append(spec)
        }
        try setPluginSpecs(specs)
    }

    static func normalizeSpecs(_ specs: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in specs {
            let spec = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !spec.isEmpty else { continue }
            let name = NpmPlugin.parse(spec).name
            guard !name.isEmpty, !seen.contains(name) else { continue }
            seen.insert(name)
            result.append(spec)
        }
        return result
    }

    // MARK: - MCP

    var mcpRaw: [String: Any] { (root["mcp"] as? [String: Any]) ?? [:] }

    var mcpServers: [MCPServer] {
        mcpRaw.compactMap { key, value in
            guard let dict = value as? [String: Any] else { return nil }
            return MCPServer(key: key, value: dict)
        }
        .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
    }

    func upsertMCP(_ server: MCPServer) throws {
        try mutate { root in
            var mcp = (root["mcp"] as? [String: Any]) ?? [:]
            mcp[server.key] = server.dictionary()
            root["mcp"] = mcp
        }
    }

    func removeMCP(key: String) throws {
        try mutate { root in
            guard var mcp = (root["mcp"] as? [String: Any]) else { return }
            mcp.removeValue(forKey: key)
            if mcp.isEmpty { root.removeValue(forKey: "mcp") } else { root["mcp"] = mcp }
        }
    }

    // MARK: - Misc

    var model: String? { root["model"] as? String }
    var schema: String? { root["$schema"] as? String }

    func summary() -> [(String, String)] {
        var rows: [(String, String)] = []
        rows.append(("Plugin entries", "\(pluginSpecs.count)"))
        rows.append(("MCP servers", "\(mcpRaw.count)"))
        if let model { rows.append(("Model", model)) }
        if let schema { rows.append(("Schema", schema)) }
        rows.append(("Total keys", "\(root.count)"))
        return rows
    }
}
