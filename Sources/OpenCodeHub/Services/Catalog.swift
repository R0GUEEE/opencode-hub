import Foundation

/// Curated starting point plus a user-editable overlay stored at
/// ~/Library/Application Support/OpenCodeHub/catalog.json.
enum Catalog {
    static let defaultEntries: [CatalogEntry] = [
        // MARK: Skills (Agent Skills format, public repository)
        CatalogEntry(id: "skill-pdf", kind: .skill, name: "PDF",
                     summary: "Fill forms, extract text and tables, merge and annotate PDF files.",
                     source: "anthropics/skills/document-skills/pdf", tags: ["documents"], verified: true, author: "Anthropic"),
        CatalogEntry(id: "skill-docx", kind: .skill, name: "Word documents",
                     summary: "Create and edit .docx files with tracked changes and comments.",
                     source: "anthropics/skills/document-skills/docx", tags: ["documents"], verified: true, author: "Anthropic"),
        CatalogEntry(id: "skill-pptx", kind: .skill, name: "PowerPoint",
                     summary: "Build and edit .pptx decks, templates, layouts and speaker notes.",
                     source: "anthropics/skills/document-skills/pptx", tags: ["documents"], verified: true, author: "Anthropic"),
        CatalogEntry(id: "skill-xlsx", kind: .skill, name: "Spreadsheets",
                     summary: "Read and write .xlsx workbooks, formulas and charts.",
                     source: "anthropics/skills/document-skills/xlsx", tags: ["documents"], verified: true, author: "Anthropic"),
        CatalogEntry(id: "skill-mcp-builder", kind: .skill, name: "MCP builder",
                     summary: "Scaffold and test a Model Context Protocol server end to end.",
                     source: "anthropics/skills/mcp-builder", tags: ["mcp", "dev"], verified: true, author: "Anthropic"),
        CatalogEntry(id: "skill-webapp-testing", kind: .skill, name: "Webapp testing",
                     summary: "Drive a browser to verify a web app, capture screenshots and report failures.",
                     source: "anthropics/skills/webapp-testing", tags: ["testing", "browser"], verified: true, author: "Anthropic"),
        CatalogEntry(id: "skill-artifacts-builder", kind: .skill, name: "Artifacts builder",
                     summary: "Produce self-contained HTML artifacts with React, Tailwind and shadcn/ui.",
                     source: "anthropics/skills/artifacts-builder", tags: ["frontend"], verified: true, author: "Anthropic"),
        CatalogEntry(id: "skill-canvas-design", kind: .skill, name: "Canvas design",
                     summary: "Compose visual designs on an HTML canvas and export them.",
                     source: "anthropics/skills/canvas-design", tags: ["design"], verified: true, author: "Anthropic"),
        CatalogEntry(id: "skill-brand-guidelines", kind: .skill, name: "Brand guidelines",
                     summary: "Apply a house style guide to generated documents and slides.",
                     source: "anthropics/skills/brand-guidelines", tags: ["design"], verified: true, author: "Anthropic"),
        CatalogEntry(id: "skill-slack-gif", kind: .skill, name: "Slack GIF creator",
                     summary: "Generate animated GIFs sized for Slack reactions and posts.",
                     source: "anthropics/skills/slack-gif-creator", tags: ["media"], verified: true, author: "Anthropic"),

        // MARK: Plugins (npm packages, unverified)
        CatalogEntry(id: "plugin-wakatime", kind: .plugin, name: "WakaTime",
                     summary: "Report opencode sessions to WakaTime for automatic time tracking.",
                     source: "opencode-wakatime", tags: ["metrics"]),
        CatalogEntry(id: "plugin-notifier", kind: .plugin, name: "Notifier",
                     summary: "Desktop notifications when a session finishes or errors out.",
                     source: "opencode-notifier", tags: ["notifications"]),
        CatalogEntry(id: "plugin-gemini-auth", kind: .plugin, name: "Gemini auth",
                     summary: "Authenticate Google Gemini models through an OAuth flow instead of an API key.",
                     source: "opencode-gemini-auth", tags: ["provider", "auth"]),
        CatalogEntry(id: "plugin-codex-auth", kind: .plugin, name: "Codex auth",
                     summary: "Use a ChatGPT subscription for OpenAI Codex models inside opencode.",
                     source: "opencode-openai-codex-auth", tags: ["provider", "auth"]),

        // MARK: Tools (built-in templates)
        CatalogEntry(id: "tool-shell", kind: .tool, name: "Run a command",
                     summary: "A custom tool that runs one whitelisted command and returns its output.",
                     source: "template-shell", tags: ["template"], verified: true),
        CatalogEntry(id: "tool-http", kind: .tool, name: "Fetch a URL",
                     summary: "A custom tool that fetches a URL and returns the body as text.",
                     source: "template-http", tags: ["template"], verified: true),
        CatalogEntry(id: "tool-json", kind: .tool, name: "Query a JSON file",
                     summary: "A custom tool that reads a JSON file and returns a dotted path.",
                     source: "template-json", tags: ["template"], verified: true),

        // MARK: MCP servers
        CatalogEntry(id: "mcp-filesystem", kind: .mcp, name: "Filesystem",
                     summary: "Filesystem access scoped to an allowed root directory.",
                     source: "filesystem", tags: ["files", "official"], verified: true, author: "Model Context Protocol"),
        CatalogEntry(id: "mcp-github", kind: .mcp, name: "GitHub",
                     summary: "Issues, pull requests and code search through a personal access token.",
                     source: "github", tags: ["git", "official"], verified: true, author: "Model Context Protocol"),
        CatalogEntry(id: "mcp-playwright", kind: .mcp, name: "Playwright",
                     summary: "Browser automation: navigate, click, type and snapshot pages.",
                     source: "playwright", tags: ["browser"], verified: true, author: "Microsoft"),
        CatalogEntry(id: "mcp-sqlite", kind: .mcp, name: "SQLite",
                     summary: "Query a local SQLite database.",
                     source: "sqlite", tags: ["database", "official"], verified: true, author: "Model Context Protocol"),
        CatalogEntry(id: "mcp-memory", kind: .mcp, name: "Memory",
                     summary: "Persistent knowledge graph shared across sessions.",
                     source: "memory", tags: ["memory", "official"], verified: true, author: "Model Context Protocol"),
        CatalogEntry(id: "mcp-context7", kind: .mcp, name: "Context7",
                     summary: "Version-accurate library documentation over a hosted HTTP endpoint.",
                     source: "context7", tags: ["docs", "remote"], verified: true, author: "Upstash"),
    ]

    static func load() -> [CatalogEntry] {
        guard let data = try? Data(contentsOf: Paths.appCatalogFile),
              let decoded = try? JSONDecoder().decode([CatalogEntry].self, from: data),
              !decoded.isEmpty else {
            return defaultEntries
        }
        return decoded
    }

    static func save(_ entries: [CatalogEntry]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FS.atomicWrite(try encoder.encode(entries), to: Paths.appCatalogFile)
    }

    static func decode(_ data: Data) throws -> [CatalogEntry] {
        try JSONDecoder().decode([CatalogEntry].self, from: data)
    }

    /// Fetches a remote catalog: either a bare JSON array or `{"entries": [...]}`.
    static func fetchRemote(_ urlString: String) async throws -> [CatalogEntry] {
        let data = try await HTTP.data(urlString, timeout: 30)
        if let entries = try? decode(data) { return entries }
        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let raw = root["entries"],
           let entryData = try? JSONSerialization.data(withJSONObject: raw),
           let entries = try? decode(entryData) {
            return entries
        }
        throw HubError.invalidInput("That URL did not return a catalog array.")
    }

    /// Live npm search restricted to the opencode plugin keyword when possible.
    static func searchPlugins(_ query: String) async throws -> [CatalogEntry] {
        let packages = try await NPMRegistry.search(query, size: 30)
        return packages.map { package in
            CatalogEntry(
                id: "npm-" + package.name,
                kind: .plugin,
                name: package.name,
                summary: package.summary,
                source: package.name,
                version: package.version.isEmpty ? nil : package.version,
                homepage: package.homepage,
                tags: package.keywords.prefix(4).map { $0 },
                verified: false,
                author: package.author
            )
        }
    }
}
