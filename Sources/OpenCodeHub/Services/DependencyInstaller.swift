import Foundation

struct InstallPlan {
    let executable: String
    let arguments: [String]
    let label: String
    let base: URL
}

enum DependencyInstaller {
    /// opencode runs `bun install` itself on startup. This is the same command,
    /// run on demand so the user does not have to restart the CLI to find out
    /// that a package failed to resolve.
    static func plan(for base: URL) -> InstallPlan? {
        if let bun = Shell.which("bun") {
            return InstallPlan(executable: bun, arguments: ["install"], label: "bun install", base: base)
        }
        if let npm = Shell.which("npm") {
            return InstallPlan(
                executable: npm,
                arguments: ["install", "--no-audit", "--no-fund"],
                label: "npm install",
                base: base
            )
        }
        return nil
    }

    static func install(
        base: URL,
        log: @escaping @Sendable (String) -> Void
    ) async throws -> ShellResult {
        guard FS.exists(base.appendingPathComponent("package.json")) else {
            throw HubError.invalidInput("There is no package.json in \(Paths.tilde(base)) yet. Add a dependency first.")
        }
        guard let plan = plan(for: base) else {
            throw HubError.invalidInput("Neither bun nor npm was found on PATH. opencode needs one of them to install packages.")
        }
        log("\(plan.label) in \(Paths.tilde(base))")
        let result = try await Shell.run(plan.executable, plan.arguments, cwd: base, timeout: 900)
        let output = result.output
        if !output.isEmpty { log(String(output.suffix(2000))) }
        guard result.succeeded else { throw ShellError.failed(result) }
        return result
    }

    /// Names declared in package.json that have no directory in node_modules.
    static func missing(base: URL, document: [String: Any]) -> [String] {
        let modules = base.appendingPathComponent("node_modules", isDirectory: true)
        var declared: [String] = []
        for section in ["dependencies", "devDependencies"] {
            guard let map = document[section] as? [String: Any] else { continue }
            declared.append(contentsOf: map.keys)
        }
        guard !declared.isEmpty else { return [] }
        guard FS.isDirectory(modules) else { return declared.sorted() }
        return declared.filter { name in
            !FS.isDirectory(modules.appendingPathComponent(name, isDirectory: true))
        }.sorted()
    }

    static func packageManager() -> String? {
        if Shell.which("bun") != nil { return "bun" }
        if Shell.which("npm") != nil { return "npm" }
        if Shell.which("pnpm") != nil { return "pnpm" }
        return nil
    }
}
