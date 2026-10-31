import Foundation
import Combine

struct BinaryStatus: Identifiable, Hashable {
    let name: String
    let path: String?
    let version: String?

    var id: String { name }
    var isPresent: Bool { path != nil }
}

/// Locates the opencode CLI and the runtimes it depends on.
///
/// A GUI process does not inherit the login shell environment, so binaries are
/// looked up through an explicit PATH built in `Shell.searchPath`.
@MainActor
final class CLI: ObservableObject {
    @Published private(set) var opencodePath: String?
    @Published private(set) var opencodeVersion: String?
    @Published private(set) var bun: BinaryStatus?
    @Published private(set) var node: BinaryStatus?
    @Published private(set) var npm: BinaryStatus?
    @Published private(set) var git: BinaryStatus?
    @Published private(set) var checkedAt: Date?

    var opencodeAvailable: Bool { opencodePath != nil }

    func refresh() async {
        opencodePath = Shell.which("opencode")
        if let path = opencodePath {
            let result = try? await Shell.run(path, ["--version"], timeout: 25)
            let text = (result?.stdout.trimmed.isEmpty == false ? result?.stdout : result?.stderr) ?? ""
            opencodeVersion = text.trimmed.firstLine
        } else {
            opencodeVersion = nil
        }

        bun = await probe("bun", args: ["--version"])
        node = await probe("node", args: ["--version"])
        npm = await probe("npm", args: ["--version"])
        git = await probe("git", args: ["--version"])
        checkedAt = Date()
    }

    private func probe(_ name: String, args: [String]) async -> BinaryStatus {
        guard let path = Shell.which(name) else {
            return BinaryStatus(name: name, path: nil, version: nil)
        }
        let result = try? await Shell.run(path, args, timeout: 20)
        var version = (result?.stdout ?? "").trimmed.firstLine
        if name == "node", version.hasPrefix("v") { version.removeFirst() }
        return BinaryStatus(name: name, path: path, version: version.isEmpty ? nil : version)
    }

    @discardableResult
    func runOpencode(_ arguments: [String], cwd: URL? = nil, timeout: TimeInterval = 180) async throws -> ShellResult {
        guard let path = opencodePath ?? Shell.which("opencode") else {
            throw ShellError.notFound("opencode")
        }
        return try await Shell.run(path, arguments, cwd: cwd, timeout: timeout)
    }

    /// Installs a plugin through the CLI's own `plugin` subcommand, which also
    /// writes the config entry. Used only when the user opts in.
    func installPluginViaCLI(_ spec: String, project: URL?) async throws {
        let result = try await runOpencode(["plugin", spec], cwd: project, timeout: 300)
        await MainActor.run { AppLog.shared.record(result) }
        guard result.succeeded else { throw ShellError.failed(result) }
    }
}
