import Foundation

/// Every filesystem location OpenCode Hub touches, resolved the same way the
/// opencode CLI resolves it (XDG variables first, then the macOS defaults).
enum Paths {
    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    static func env(_ key: String) -> String? {
        guard let value = ProcessInfo.processInfo.environment[key], !value.isEmpty else { return nil }
        return value
    }

    static var xdgConfig: URL {
        if let raw = env("XDG_CONFIG_HOME") { return URL(fileURLWithPath: raw, isDirectory: true) }
        return home.appendingPathComponent(".config", isDirectory: true)
    }

    static var xdgCache: URL {
        if let raw = env("XDG_CACHE_HOME") { return URL(fileURLWithPath: raw, isDirectory: true) }
        return home.appendingPathComponent(".cache", isDirectory: true)
    }

    static var xdgData: URL {
        if let raw = env("XDG_DATA_HOME") { return URL(fileURLWithPath: raw, isDirectory: true) }
        return home.appendingPathComponent(".local/share", isDirectory: true)
    }

    /// ~/.config/opencode
    static var configDir: URL { xdgConfig.appendingPathComponent("opencode", isDirectory: true) }
    static var configFile: URL { configDir.appendingPathComponent("opencode.json") }
    static var tuiConfigFile: URL { configDir.appendingPathComponent("tui.json") }

    // opencode uses PLURAL directory names; singular names are a legacy fallback.
    static var globalPluginsDir: URL { configDir.appendingPathComponent("plugins", isDirectory: true) }
    static var globalSkillsDir: URL { configDir.appendingPathComponent("skills", isDirectory: true) }
    static var globalToolsDir: URL { configDir.appendingPathComponent("tools", isDirectory: true) }
    static var globalAgentsDir: URL { configDir.appendingPathComponent("agents", isDirectory: true) }
    static var globalCommandsDir: URL { configDir.appendingPathComponent("commands", isDirectory: true) }
    static var globalThemesDir: URL { configDir.appendingPathComponent("themes", isDirectory: true) }
    static var configPackageJSON: URL { configDir.appendingPathComponent("package.json") }

    /// ~/.cache/opencode
    static var cacheDir: URL { xdgCache.appendingPathComponent("opencode", isDirectory: true) }
    static var nodeModulesCache: URL { cacheDir.appendingPathComponent("node_modules", isDirectory: true) }

    /// ~/.local/share/opencode
    static var dataDir: URL { xdgData.appendingPathComponent("opencode", isDirectory: true) }
    static var authFile: URL { dataDir.appendingPathComponent("auth.json") }
    static var logDir: URL { dataDir.appendingPathComponent("log", isDirectory: true) }

    /// ~/Library/Application Support/OpenCodeHub
    static var appSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? home.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("OpenCodeHub", isDirectory: true)
    }
    static var backupsDir: URL { appSupport.appendingPathComponent("Backups", isDirectory: true) }
    static var appLogFile: URL { appSupport.appendingPathComponent("hub.log") }
    static var appCatalogFile: URL { appSupport.appendingPathComponent("catalog.json") }
    static var appSettingsFile: URL { appSupport.appendingPathComponent("settings.json") }
    static var stagingDir: URL { appSupport.appendingPathComponent("Staging", isDirectory: true) }

    static var projectMarkers: [String] { ["opencode.json", "opencode.jsonc", ".opencode"] }

    /// Walks up from `start` looking for a project-level opencode.json or .opencode/.
    static func projectRoot(startingAt start: URL) -> URL? {
        var current = start.standardizedFileURL
        for _ in 0..<12 {
            for marker in projectMarkers {
                let candidate = current.appendingPathComponent(marker)
                if FileManager.default.fileExists(atPath: candidate.path) { return current }
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
        }
        return nil
    }

    static func projectPluginsDir(_ root: URL) -> URL { root.appendingPathComponent(".opencode/plugins", isDirectory: true) }
    static func projectSkillsDir(_ root: URL) -> URL { root.appendingPathComponent(".opencode/skills", isDirectory: true) }
    static func projectToolsDir(_ root: URL) -> URL { root.appendingPathComponent(".opencode/tools", isDirectory: true) }

    static func ensure(_ url: URL) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: url.path, isDirectory: &isDir) {
            if !isDir.boolValue { throw HubError.notADirectory(url.path) }
            return
        }
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
    }

    static func tilde(_ url: URL) -> String {
        let path = url.path
        let homePath = home.path
        if path == homePath { return "~" }
        if path.hasPrefix(homePath + "/") { return "~" + path.dropFirst(homePath.count) }
        return path
    }
}

enum HubError: LocalizedError {
    case notADirectory(String)
    case invalidInput(String)
    case notFound(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .notADirectory(let path): return "\(path) exists but is not a directory."
        case .invalidInput(let message): return message
        case .notFound(let message): return message
        case .cancelled: return "Cancelled."
        }
    }
}
