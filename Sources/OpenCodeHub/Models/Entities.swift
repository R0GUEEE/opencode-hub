import Foundation

enum InstallKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case plugin, skill, tool, mcp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plugin: return "Plugin"
        case .skill: return "Skill"
        case .tool: return "Tool"
        case .mcp: return "MCP server"
        }
    }

    var plural: String {
        switch self {
        case .plugin: return "Plugins"
        case .skill: return "Skills"
        case .tool: return "Tools"
        case .mcp: return "MCP servers"
        }
    }

    var symbol: String {
        switch self {
        case .plugin: return "puzzlepiece.extension"
        case .skill: return "book.closed"
        case .tool: return "wrench.and.screwdriver"
        case .mcp: return "antenna.radiowaves.left.and.right"
        }
    }
}

/// A package reference from the `plugin` array of opencode.json.
struct NpmPlugin: Identifiable, Hashable {
    let spec: String
    let name: String
    let version: String?

    var id: String { spec }
    var versionText: String { version ?? "latest" }

    init(spec: String) {
        let cleaned = spec.trimmingCharacters(in: .whitespacesAndNewlines)
        self.spec = cleaned
        let parsed = NpmPlugin.parse(cleaned)
        self.name = parsed.name
        self.version = parsed.version
    }

    /// Handles scoped packages: @scope/name@1.2.3
    static func parse(_ spec: String) -> (name: String, version: String?) {
        let trimmed = spec.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ("", nil) }
        if trimmed.hasPrefix("@") {
            if let at = trimmed.dropFirst().firstIndex(of: "@") {
                let name = String(trimmed[trimmed.startIndex..<at])
                let version = String(trimmed[trimmed.index(after: at)...])
                return (name, version.isEmpty ? nil : version)
            }
            return (trimmed, nil)
        }
        if let at = trimmed.firstIndex(of: "@") {
            let name = String(trimmed[trimmed.startIndex..<at])
            let version = String(trimmed[trimmed.index(after: at)...])
            return (name, version.isEmpty ? nil : version)
        }
        return (trimmed, nil)
    }
}

struct LocalPlugin: Identifiable, Hashable {
    let fileName: String
    let url: URL
    let size: Int64
    let modified: Date?
    let scope: Scope

    enum Scope: String { case global, project }

    var id: String { scope.rawValue + "/" + fileName }
    var language: String { url.pathExtension.lowercased() }

    var symbol: String {
        switch language {
        case "ts", "mts": return "swift"
        case "js", "mjs", "cjs": return "curlybraces"
        default: return "doc"
        }
    }
}

struct Skill: Identifiable, Hashable {
    let slug: String
    var name: String
    var summary: String
    var path: URL
    var fileCount: Int
    var modified: Date?
    var scope: Scope
    var license: String?

    enum Scope: String { case global, project }

    var id: String { scope.rawValue + "/" + slug }
    var displayName: String { name.isEmpty ? slug : name }
    var body: String? { FS.read(path.appendingPathComponent("SKILL.md")) }
}

struct ToolFile: Identifiable, Hashable {
    let fileName: String
    let url: URL
    let size: Int64
    let modified: Date?

    var id: String { fileName }
    var stem: String { (fileName as NSString).deletingPathExtension }
    var language: String { url.pathExtension.lowercased() }
}

struct MCPServer: Identifiable, Hashable {
    let key: String
    var type: String
    var command: [String]
    var url: String?
    var enabled: Bool
    var environment: [String: String]
    var headers: [String: String]

    var id: String { key }
    var isRemote: Bool { type == "remote" }

    var summary: String {
        if isRemote { return url ?? "remote" }
        return command.isEmpty ? "no command" : command.joined(separator: " ")
    }

    init?(key: String, value: [String: Any]) {
        guard !key.isEmpty else { return nil }
        self.key = key
        self.type = (value["type"] as? String) ?? "local"
        self.command = JSONC.stringArray(value["command"])
        self.url = value["url"] as? String
        self.enabled = JSONC.bool(value["enabled"]) ?? true
        self.environment = JSONC.stringMap(value["environment"])
        self.headers = JSONC.stringMap(value["headers"])
    }

    init(key: String, type: String, command: [String], url: String?, enabled: Bool,
         environment: [String: String], headers: [String: String]) {
        self.key = key
        self.type = type
        self.command = command
        self.url = url
        self.enabled = enabled
        self.environment = environment
        self.headers = headers
    }

    func dictionary() -> [String: Any] {
        var dict: [String: Any] = ["type": type, "enabled": enabled]
        if isRemote {
            if let url, !url.isEmpty { dict["url"] = url }
            if !headers.isEmpty { dict["headers"] = headers }
        } else {
            dict["command"] = command
            if !environment.isEmpty { dict["environment"] = environment }
        }
        return dict
    }
}

struct CatalogEntry: Identifiable, Hashable, Codable {
    var id: String
    var kind: InstallKind
    var name: String
    var summary: String
    /// GitHub `owner/repo[/subpath]`, an npm spec, a URL, or a built-in template id.
    var source: String
    var version: String?
    var homepage: String?
    var tags: [String]
    var verified: Bool
    var author: String?

    init(id: String, kind: InstallKind, name: String, summary: String, source: String,
         version: String? = nil, homepage: String? = nil, tags: [String] = [],
         verified: Bool = false, author: String? = nil) {
        self.id = id
        self.kind = kind
        self.name = name
        self.summary = summary
        self.source = source
        self.version = version
        self.homepage = homepage
        self.tags = tags
        self.verified = verified
        self.author = author
    }
}

struct HealthItem: Identifiable {
    enum State { case ok, warn, bad }

    let id: String
    let title: String
    let detail: String
    let state: State
    let symbol: String
}
