import Foundation

@MainActor
extension Workspace {
    func performMCPPreset(_ preset: MCPPreset) {
        Task {
            await perform("Adding \(preset.name)") { [self] in
                try config.upsertMCP(preset.server)
                log.success("Added MCP server \(preset.server.key)")
            }
        }
    }

    func resetCatalog() {
        catalog = Catalog.defaultEntries
        do {
            try Catalog.save(catalog)
            notice = "Catalog reset to the bundled set"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func revealBackups() {
        try? Paths.ensure(Paths.backupsDir)
        reveal(Paths.backupsDir)
    }
}

enum DependencyScope: String, CaseIterable, Identifiable {
    case global, project

    var id: String { rawValue }

    var title: String {
        switch self {
        case .global: return "Global"
        case .project: return "Project"
        }
    }
}

@MainActor
extension Workspace {
    /// Base directory holding package.json for a scope. The project variant is
    /// `<project>/.opencode`, which is where opencode runs `bun install` for
    /// project-level plugins and tools.
    func dependencyBase(for scope: DependencyScope) -> URL? {
        switch scope {
        case .global:
            return Paths.configDir
        case .project:
            guard let projectRoot else { return nil }
            return projectRoot.appendingPathComponent(".opencode", isDirectory: true)
        }
    }

    func loadDependencies(_ scope: DependencyScope) {
        guard let base = dependencyBase(for: scope) else { return }
        dependencyScope = scope
        dependencies.load(base: base)
    }

    func addDependency(name: String, requirement: String, section: DependencySection) async {
        await perform("Adding \(name)") { [self] in
            try dependencies.add(name: name, requirement: requirement, section: section)
            log.success("Declared \(name) in \(Paths.tilde(dependencies.fileURL))")
        }
    }

    func removeDependency(_ dependency: PackageDependency) async {
        await perform("Removing \(dependency.name)") { [self] in
            try dependencies.remove(dependency)
            log.info("Removed \(dependency.name) from package.json")
        }
    }

    func setDependencyRequirement(_ dependency: PackageDependency, requirement: String) async {
        await perform("Updating \(dependency.name)") { [self] in
            try dependencies.setRequirement(dependency, to: requirement)
        }
    }

    func clearDependencies() async {
        await perform("Clearing dependencies") { [self] in
            try dependencies.clearDependencies()
            log.info("Removed every dependency entry")
        }
    }

    func installDependencies() async {
        await perform("Installing dependencies") { [self] in
            _ = try await DependencyInstaller.install(base: dependencies.base, log: logger())
            dependencies.reload()
            log.success("Installed \(dependencies.installedCount) packages in \(Paths.tilde(dependencies.base))")
        }
    }

    /// Resolves bare "latest" or "*" entries against the npm registry and writes
    /// caret ranges, matching what `bun add` would have written.
    func pinDependenciesToLatest() async {
        await perform("Resolving versions") { [self] in
            var resolved: [String: String] = [:]
            for dependency in dependencies.packages
            where dependency.requirement == "latest" || dependency.requirement == "*" {
                if let info = try? await NPMRegistry.info(dependency.name) {
                    resolved[dependency.name] = info.version
                }
            }
            let changed = try dependencies.pinResolved(resolved)
            log.success(changed.isEmpty ? "Nothing needed pinning" : "Pinned: \(changed.joined(separator: ", "))")
        }
    }

    func openDependencyFolder() {
        try? FS.ensure(dependencies.base)
        openFolder(dependencies.base)
    }

    func revealPackageJSON() {
        if FS.exists(dependencies.fileURL) {
            reveal(dependencies.fileURL)
        } else {
            openDependencyFolder()
        }
    }
}
