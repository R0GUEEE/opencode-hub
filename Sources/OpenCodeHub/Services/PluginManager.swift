import Foundation

enum PluginManager {
    static let allowedExtensions: Set<String> = ["js", "mjs", "cjs", "ts", "mts"]

    static func localPlugins(in directory: URL, scope: LocalPlugin.Scope) -> [LocalPlugin] {
        FS.children(directory, extensions: allowedExtensions).compactMap { url in
            guard !FS.isDirectory(url) else { return nil }
            return LocalPlugin(
                fileName: url.lastPathComponent,
                url: url,
                size: FS.size(url),
                modified: FS.modified(url),
                scope: scope
            )
        }
        .sorted { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending }
    }

    /// Copies a plugin file into the plugins directory. Existing files with the
    /// same name are moved to the Trash first, so nothing is silently lost.
    static func installLocalFile(_ source: URL, to directory: URL, log: @escaping @Sendable (String) -> Void) throws -> LocalPlugin {
        let ext = source.pathExtension.lowercased()
        guard allowedExtensions.contains(ext) else {
            throw HubError.invalidInput("Plugins must be .js, .mjs, .cjs, .ts or .mts files. Got .\(ext)")
        }
        let text = FS.read(source) ?? ""
        guard !text.trimmed.isEmpty else {
            throw HubError.invalidInput("\(source.lastPathComponent) is empty.")
        }
        try FS.ensure(directory)
        let destination = directory.appendingPathComponent(source.lastPathComponent)
        if FS.exists(destination) {
            try? FS.trash(destination)
            log("Replaced \(source.lastPathComponent)")
        }
        try FileManager.default.copyItem(at: source, to: destination)
        log("Installed plugin \(source.lastPathComponent) to \(Paths.tilde(directory))")
        return LocalPlugin(
            fileName: destination.lastPathComponent,
            url: destination,
            size: FS.size(destination),
            modified: FS.modified(destination),
            scope: directory.path.contains("/.opencode/") ? .project : .global
        )
    }

    static func writeLocalPlugin(name: String, contents: String, to directory: URL) throws -> LocalPlugin {
        let fileName = name.hasSuffix(".ts") || name.hasSuffix(".js") ? name : name + ".ts"
        try FS.ensure(directory)
        let destination = directory.appendingPathComponent(fileName)
        try FS.atomicWrite(contents, to: destination)
        return LocalPlugin(
            fileName: fileName,
            url: destination,
            size: FS.size(destination),
            modified: FS.modified(destination),
            scope: directory.path.contains("/.opencode/") ? .project : .global
        )
    }

    static func deleteLocal(_ plugin: LocalPlugin) throws {
        try FS.trash(plugin.url)
    }

    /// npm plugins declared in config are installed by opencode with Bun at
    /// startup; prefetching here just warms the shared cache.
    static func prefetch(specs: [String], log: @escaping @Sendable (String) -> Void) async throws {
        guard !specs.isEmpty else { return }
        guard let bun = Shell.which("bun") else {
            throw HubError.invalidInput("bun was not found. opencode installs npm plugins with Bun at startup; install Bun to prefetch.")
        }
        try FS.ensure(Paths.cacheDir)
        var arguments = ["add", "--no-save"]
        arguments.append(contentsOf: specs)
        log("bun " + arguments.joined(separator: " "))
        let result = try await Shell.run(bun, arguments, cwd: Paths.cacheDir, timeout: 300)
        log(result.output.isEmpty ? "bun finished with status \(result.status)" : String(result.output.suffix(1200)))
        guard result.succeeded else { throw ShellError.failed(result) }
    }
}
