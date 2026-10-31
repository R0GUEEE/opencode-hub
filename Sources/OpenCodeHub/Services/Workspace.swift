import Foundation
import Combine
import AppKit

@MainActor
final class HubSettings: ObservableObject {
    static let shared = HubSettings()

    private let defaults = UserDefaults.standard

    @Published var installPluginsWithCLI: Bool {
        didSet { defaults.set(installPluginsWithCLI, forKey: "installPluginsWithCLI") }
    }
    @Published var prefetchAfterInstall: Bool {
        didSet { defaults.set(prefetchAfterInstall, forKey: "prefetchAfterInstall") }
    }
    @Published var showProjectScope: Bool {
        didSet { defaults.set(showProjectScope, forKey: "showProjectScope") }
    }
    @Published var remoteCatalogURL: String {
        didSet { defaults.set(remoteCatalogURL, forKey: "remoteCatalogURL") }
    }
    @Published var lastProjectPath: String {
        didSet { defaults.set(lastProjectPath, forKey: "lastProjectPath") }
    }

    init() {
        defaults.register(defaults: [
            "installPluginsWithCLI": false,
            "prefetchAfterInstall": false,
            "showProjectScope": true,
            "remoteCatalogURL": "",
            "lastProjectPath": "",
        ])
        installPluginsWithCLI = defaults.bool(forKey: "installPluginsWithCLI")
        prefetchAfterInstall = defaults.bool(forKey: "prefetchAfterInstall")
        showProjectScope = defaults.bool(forKey: "showProjectScope")
        remoteCatalogURL = defaults.string(forKey: "remoteCatalogURL") ?? ""
        lastProjectPath = defaults.string(forKey: "lastProjectPath") ?? ""
    }
}

/// Single source of truth for the UI: config document + directory scans + jobs.
@MainActor
final class Workspace: ObservableObject {
    static let shared = Workspace()

    let config = ConfigStore()
    let cli = CLI()
    var settings: HubSettings { HubSettings.shared }
    var log: AppLog { AppLog.shared }

    @Published var npmPlugins: [NpmPlugin] = []
    @Published var localPlugins: [LocalPlugin] = []
    @Published var projectPlugins: [LocalPlugin] = []
    @Published var skills: [Skill] = []
    @Published var projectSkills: [Skill] = []
    @Published var tools: [ToolFile] = []
    @Published var projectTools: [ToolFile] = []
    @Published var servers: [MCPServer] = []
    @Published var dependencyScope: DependencyScope = .global
    let dependencies = DependencyStore(base: Paths.configDir)
    @Published var catalog: [CatalogEntry] = Catalog.load()

    @Published var busy: String?
    @Published var errorMessage: String?
    @Published var notice: String?
    @Published var projectRoot: URL?
    @Published var lastRefresh = Date()

    private var bootstrapped = false
    private var dependencyForwarder: AnyCancellable?

    init() {
        // Nested ObservableObjects do not propagate on their own; forward so the
        // sidebar badge and the dependency screen stay in sync.
        dependencyForwarder = dependencies.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    var allSkills: [Skill] { skills + projectSkills }
    var allTools: [ToolFile] { tools + projectTools }
    var allLocalPlugins: [LocalPlugin] { localPlugins + projectPlugins }

    // MARK: - Lifecycle

    func bootstrap() async {
        guard !bootstrapped else { return }
        bootstrapped = true
        resolveProject()
        await cli.refresh()
        refresh()
    }

    func refresh() {
        config.reload()
        npmPlugins = config.pluginSpecs.map { NpmPlugin(spec: $0) }
        localPlugins = PluginManager.localPlugins(in: Paths.globalPluginsDir, scope: .global)
        projectPlugins = projectRoot.map {
            PluginManager.localPlugins(in: Paths.projectPluginsDir($0), scope: .project)
        } ?? []
        skills = SkillManager.installed(scope: .global, base: Paths.globalSkillsDir)
        projectSkills = projectRoot.map {
            SkillManager.installed(scope: .project, base: Paths.projectSkillsDir($0))
        } ?? []
        tools = ToolManager.installed(in: Paths.globalToolsDir)
        projectTools = projectRoot.map {
            ToolManager.installed(in: Paths.projectToolsDir($0))
        } ?? []
        servers = config.mcpServers
        if let base = dependencyBase(for: dependencyScope) { dependencies.load(base: base) }
        lastRefresh = Date()
    }

    func resolveProject() {
        if !settings.lastProjectPath.isEmpty {
            let url = URL(fileURLWithPath: settings.lastProjectPath, isDirectory: true)
            if FS.isDirectory(url) { projectRoot = url; return }
        }
        projectRoot = Paths.projectRoot(startingAt: Paths.home)
    }

    func chooseProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Pick the folder opencode runs in"
        panel.prompt = "Use Folder"
        if panel.runModal() == .OK, let url = panel.url {
            projectRoot = url
            settings.lastProjectPath = url.path
            refresh()
            log.info("Project scope set to \(Paths.tilde(url))")
        }
    }

    func clearProject() {
        projectRoot = nil
        settings.lastProjectPath = ""
        refresh()
    }

    // MARK: - Job wrapper

    func perform(_ label: String, _ work: @escaping @MainActor () async throws -> Void) async {
        if busy != nil { return }
        busy = label
        errorMessage = nil
        defer { busy = nil }
        do {
            try await work()
            refresh()
        } catch {
            errorMessage = error.localizedDescription
            log.error("\(label) failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Catalog

    var installedCatalogIDs: Set<String> {
        var ids = Set<String>()
        for entry in catalog {
            switch entry.kind {
            case .plugin:
                let name = NpmPlugin(spec: entry.source).name
                if npmPlugins.contains(where: { $0.name == name }) { ids.insert(entry.id) }
            case .skill:
                if allSkills.contains(where: { $0.displayName.caseInsensitiveCompare(entry.name) == .orderedSame }) {
                    ids.insert(entry.id)
                }
            case .tool:
                if let template = ToolManager.templates.first(where: { $0.id == entry.source }),
                   allTools.contains(where: { $0.fileName == template.fileName }) {
                    ids.insert(entry.id)
                }
            case .mcp:
                if servers.contains(where: { $0.key == entry.source }) { ids.insert(entry.id) }
            }
        }
        return ids
    }

    func install(_ entry: CatalogEntry, scope: Skill.Scope = .global) async {
        await perform("Installing \(entry.name)") { [self] in
            switch entry.kind {
            case .plugin:
                try await installPlugin(entry.source, scope: .global)
            case .skill:
                _ = try await SkillManager.installFromGitHub(
                    entry.source, scope: scope, projectRoot: projectRoot, log: logger()
                )
            case .tool:
                guard let template = ToolManager.templates.first(where: { $0.id == entry.source }) else {
                    throw HubError.notFound("Unknown tool template \(entry.source).")
                }
                let directory = scope == .project && projectRoot != nil
                    ? Paths.projectToolsDir(projectRoot!)
                    : Paths.globalToolsDir
                let saved = try ToolManager.save(name: template.fileName, contents: template.body, in: directory)
                log.success("Installed tool \(saved.fileName)")
            case .mcp:
                guard let preset = MCPPreset.all.first(where: { $0.id == entry.source }) else {
                    throw HubError.notFound("Unknown MCP preset \(entry.source).")
                }
                try config.upsertMCP(preset.server)
                log.success("Added MCP server \(preset.server.key)")
            }
        }
    }

    func logger() -> @Sendable (String) -> Void {
        { message in
            Task { @MainActor in AppLog.shared.info(message) }
        }
    }

    // MARK: - Plugins

    func installPlugin(_ spec: String, scope: Skill.Scope) async throws {
        let trimmed = spec.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw HubError.invalidInput("Enter an npm package name.") }

        if settings.installPluginsWithCLI, cli.opencodeAvailable {
            log.info("Running opencode plugin \(trimmed)")
            try await cli.installPluginViaCLI(trimmed, project: scope == .project ? projectRoot : nil)
            config.reload()
            if !config.pluginSpecs.contains(where: { NpmPlugin(spec: $0).name == NpmPlugin(spec: trimmed).name }) {
                try config.addPluginSpec(trimmed)
            }
        } else {
            try config.addPluginSpec(trimmed)
            log.success("Added \(trimmed) to the plugin list")
        }

        if settings.prefetchAfterInstall {
            do {
                try await PluginManager.prefetch(specs: [trimmed], log: logger())
            } catch {
                log.warn("Prefetch skipped: \(error.localizedDescription)")
            }
        }
    }

    func removePlugin(_ plugin: NpmPlugin) {
        Task {
            await perform("Removing \(plugin.name)") { [self] in
                try config.removePluginSpec(named: plugin.name)
                log.info("Removed \(plugin.name) from the plugin list")
            }
        }
    }

    func pin(_ plugin: NpmPlugin, version: String?) {
        Task {
            await perform("Updating \(plugin.name)") { [self] in
                try config.setPluginVersion(name: plugin.name, version: version)
            }
        }
    }

    func addLocalPlugin(from url: URL) async {
        await perform("Adding plugin") { [self] in
            _ = try PluginManager.installLocalFile(url, to: Paths.globalPluginsDir, log: logger())
        }
    }

    func deleteLocalPlugin(_ plugin: LocalPlugin) {
        Task {
            await perform("Deleting \(plugin.fileName)") { [self] in
                try PluginManager.deleteLocal(plugin)
                log.info("Moved \(plugin.fileName) to the Trash")
            }
        }
    }

    func prefetchAllPlugins() async {
        await perform("Prefetching plugins") { [self] in
            try await PluginManager.prefetch(specs: npmPlugins.map(\.spec), log: logger())
        }
    }

    // MARK: - Skills

    func installSkill(source: String, scope: Skill.Scope) async {
        await perform("Installing skill") { [self] in
            let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw HubError.invalidInput("Paste a GitHub repo, subfolder or SKILL.md URL.") }
            if trimmed.hasPrefix("http"), trimmed.lowercased().hasSuffix(".md") {
                _ = try await SkillManager.installFromRemoteFile(trimmed, scope: scope, projectRoot: projectRoot, log: logger())
            } else if trimmed.hasPrefix("http") || GitHubSource.parse(trimmed) != nil {
                _ = try await SkillManager.installFromGitHub(trimmed, scope: scope, projectRoot: projectRoot, log: logger())
            } else {
                let url = URL(fileURLWithPath: trimmed)
                guard FS.isDirectory(url) else {
                    throw HubError.invalidInput("That is neither a GitHub reference nor an existing folder.")
                }
                _ = try SkillManager.installDirectory(url, scope: scope, projectRoot: projectRoot, log: logger())
            }
        }
    }

    func installSkillFromFolder(scope: Skill.Scope) async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.message = "Pick a skill folder containing SKILL.md"
        panel.prompt = "Install"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        await perform("Installing \(url.lastPathComponent)") { [self] in
            _ = try SkillManager.installDirectory(url, scope: scope, projectRoot: projectRoot, log: logger())
        }
    }

    func uninstall(_ skill: Skill) {
        Task {
            await perform("Removing \(skill.displayName)") { [self] in
                try SkillManager.uninstall(skill)
                log.info("Moved \(skill.slug) to the Trash")
            }
        }
    }

    // MARK: - Tools

    func saveTool(name: String, contents: String, scope: Skill.Scope) {
        Task {
            await perform("Saving tool") { [self] in
                let directory = scope == .project && projectRoot != nil
                    ? Paths.projectToolsDir(projectRoot!)
                    : Paths.globalToolsDir
                let saved = try ToolManager.save(name: name, contents: contents, in: directory)
                log.success("Saved \(saved.fileName)")
            }
        }
    }

    func deleteTool(_ tool: ToolFile) {
        Task {
            await perform("Deleting \(tool.fileName)") { [self] in
                try ToolManager.delete(tool)
                log.info("Moved \(tool.fileName) to the Trash")
            }
        }
    }

    // MARK: - MCP

    func addMCP(key: String, type: String, command: String, url: String, environment: String) {
        Task {
            await perform("Adding MCP server") { [self] in
                var server = try MCPManager.validate(
                    key: key, type: type,
                    command: MCPManager.splitCommand(command),
                    url: url
                )
                server.environment = MCPManager.parseEnvironment(environment)
                try config.upsertMCP(server)
                log.success("Added MCP server \(server.key)")
            }
        }
    }

    func setMCPEnabled(_ server: MCPServer, enabled: Bool) {
        Task {
            await perform("Updating \(server.key)") { [self] in
                var updated = server
                updated.enabled = enabled
                try config.upsertMCP(updated)
            }
        }
    }

    func removeMCP(_ server: MCPServer) {
        Task {
            await perform("Removing \(server.key)") { [self] in
                try config.removeMCP(key: server.key)
                log.info("Removed MCP server \(server.key)")
            }
        }
    }

    // MARK: - Config helpers

    func createConfigIfNeeded() {
        do {
            try config.ensureFileExists()
            refresh()
            notice = "Created \(Paths.tilde(config.url))"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reloadConfig() {
        config.reload()
        refresh()
        notice = "Reloaded opencode.json"
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openConfig() {
        NSWorkspace.shared.open(config.url)
    }

    func openFolder(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        notice = "Copied to clipboard"
    }

    func loadRemoteCatalog() async {
        let urlString = settings.remoteCatalogURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlString.isEmpty else {
            errorMessage = "Set a catalog URL in Settings first."
            return
        }
        await perform("Loading catalog") { [self] in
            let remote = try await Catalog.fetchRemote(urlString)
            var merged = Catalog.defaultEntries
            var seen = Set(merged.map(\.id))
            for entry in remote where !seen.contains(entry.id) {
                merged.append(entry)
                seen.insert(entry.id)
            }
            catalog = merged
            try Catalog.save(merged)
            log.success("Loaded \(remote.count) catalog entries from \(urlString)")
        }
    }

    func searchNpm(_ query: String) async -> [NpmPackage] {
        (try? await NPMRegistry.search(query)) ?? []
    }

    // MARK: - Health

    var health: [HealthItem] {
        var items: [HealthItem] = []

        if let version = cli.opencodeVersion, !version.isEmpty {
            items.append(HealthItem(id: "opencode", title: "opencode CLI", detail: version,
                                    state: .ok, symbol: "terminal"))
        } else if cli.opencodeAvailable {
            items.append(HealthItem(id: "opencode", title: "opencode CLI", detail: "Found but did not report a version",
                                    state: .warn, symbol: "terminal"))
        } else {
            items.append(HealthItem(id: "opencode", title: "opencode CLI", detail: "Not on PATH — install opencode to use these entries",
                                    state: .warn, symbol: "terminal"))
        }

        if let loadError = config.loadError {
            items.append(HealthItem(id: "config", title: "opencode.json", detail: loadError, state: .bad, symbol: "doc.badge.gearshape"))
        } else if config.fileExists {
            items.append(HealthItem(id: "config", title: "opencode.json", detail: Paths.tilde(config.url),
                                    state: .ok, symbol: "doc.badge.gearshape"))
        } else {
            items.append(HealthItem(id: "config", title: "opencode.json", detail: "Not created yet",
                                    state: .warn, symbol: "doc.badge.gearshape"))
        }

        let bun = cli.bun
        items.append(HealthItem(
            id: "bun", title: "Bun",
            detail: bun?.isPresent == true ? (bun?.version ?? "present") : "Missing — opencode uses Bun to install npm plugins",
            state: bun?.isPresent == true ? .ok : .warn,
            symbol: "flame"
        ))

        let pluginsFolder = FS.isDirectory(Paths.globalPluginsDir)
        items.append(HealthItem(
            id: "dirs", title: "Config folders",
            detail: pluginsFolder ? "plugins/ and skills/ are writable" : "plugins/ not created yet",
            state: pluginsFolder ? .ok : .warn,
            symbol: "folder"
        ))

        items.append(HealthItem(
            id: "backup", title: "Backups",
            detail: FS.isDirectory(Paths.backupsDir) ? Paths.tilde(Paths.backupsDir) : "None yet",
            state: .ok,
            symbol: "clock.arrow.circlepath"
        ))

        if dependencies.exists, !dependencies.packages.isEmpty, !dependencies.nodeModulesPresent {
            items.append(HealthItem(
                id: "dependencies",
                title: "npm dependencies",
                detail: "\(dependencies.packages.count) declared in package.json but node_modules is missing — open Dependencies and install",
                state: .warn,
                symbol: "shippingbox"
            ))
        }

        return items
    }
}
