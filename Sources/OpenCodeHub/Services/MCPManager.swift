import Foundation

struct MCPPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let summary: String
    let server: MCPServer

    static func make(_ id: String, _ name: String, _ summary: String,
                     command: [String], environment: [String: String] = [:]) -> MCPPreset {
        MCPPreset(
            id: id,
            name: name,
            summary: summary,
            server: MCPServer(key: id, type: "local", command: command, url: nil,
                              enabled: true, environment: environment, headers: [:])
        )
    }

    static func makeRemote(_ id: String, _ name: String, _ summary: String, url: String) -> MCPPreset {
        MCPPreset(
            id: id,
            name: name,
            summary: summary,
            server: MCPServer(key: id, type: "remote", command: [], url: url,
                              enabled: true, environment: [:], headers: [:])
        )
    }

    static let all: [MCPPreset] = [
        make("filesystem", "Filesystem",
             "Read and write files under an allowed root.",
             command: ["npx", "-y", "@modelcontextprotocol/server-filesystem", "~/Projects"]),
        make("github", "GitHub",
             "Issues, pull requests and repository search over the GitHub API.",
             command: ["npx", "-y", "@modelcontextprotocol/server-github"],
             environment: ["GITHUB_PERSONAL_ACCESS_TOKEN": ""]),
        make("playwright", "Playwright",
             "Drive a real browser: navigate, click, fill and read pages.",
             command: ["npx", "-y", "@playwright/mcp@latest"]),
        make("sqlite", "SQLite",
             "Query a local SQLite database.",
             command: ["npx", "-y", "@modelcontextprotocol/server-sqlite", "~/data/app.db"]),
        make("memory", "Memory",
             "A knowledge graph the model can read and write across sessions.",
             command: ["npx", "-y", "@modelcontextprotocol/server-memory"]),
        makeRemote("context7", "Context7",
                   "Up-to-date library documentation served over HTTP.",
                   url: "https://mcp.context7.com/mcp"),
    ]
}

enum MCPManager {
    static func validate(key: String, type: String, command: [String], url: String) throws -> MCPServer {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw HubError.invalidInput("Give the server a key.") }
        guard trimmedKey.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil else {
            throw HubError.invalidInput("Server keys may only contain letters, digits, dot, dash and underscore.")
        }

        if type == "remote" {
            let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let parsed = URL(string: trimmedURL), let scheme = parsed.scheme,
                  scheme == "http" || scheme == "https", parsed.host != nil else {
                throw HubError.invalidInput("Remote servers need an http(s) URL.")
            }
            return MCPServer(key: trimmedKey, type: "remote", command: [], url: trimmedURL,
                             enabled: true, environment: [:], headers: [:])
        }

        let parts = command.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let executable = parts.first else {
            throw HubError.invalidInput("Local servers need a command, for example: npx -y @modelcontextprotocol/server-filesystem ~/Projects")
        }
        guard executable.range(of: #"^[A-Za-z0-9._/@:+-]+$"#, options: .regularExpression) != nil else {
            throw HubError.invalidInput("The first command word must be an executable path or name.")
        }
        return MCPServer(key: trimmedKey, type: "local", command: parts, url: nil,
                         enabled: true, environment: [:], headers: [:])
    }

    static func splitCommand(_ text: String) -> [String] {
        text.split(separator: " ").map(String.init).filter { !$0.isEmpty }
    }

    static func environmentText(_ map: [String: String]) -> String {
        map.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
    }

    static func parseEnvironment(_ text: String) -> [String: String] {
        var map: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            guard let equals = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[trimmed.startIndex..<equals]).trimmed
            let value = String(trimmed[trimmed.index(after: equals)...]).trimmed
            if !key.isEmpty { map[key] = value }
        }
        return map
    }
}
