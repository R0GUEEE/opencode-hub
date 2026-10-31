import Foundation
import Combine

enum DependencySection: String, CaseIterable, Identifiable, Codable {
    case dependencies
    case devDependencies

    var id: String { rawValue }

    var title: String { self == .dependencies ? "Runtime" : "Development" }

    var symbol: String { self == .dependencies ? "shippingbox" : "hammer" }
}

/// One entry of package.json's dependency maps.
struct PackageDependency: Identifiable, Hashable {
    let name: String
    var requirement: String
    let section: DependencySection

    var id: String { section.rawValue + ":" + name }

    var isLocal: Bool {
        requirement.hasPrefix("file:") || requirement.hasPrefix("link:")
            || requirement.hasPrefix("workspace:") || requirement.hasPrefix(".")
    }

    var displayRequirement: String { requirement.isEmpty ? "latest" : requirement }
}

/// Owns a `package.json` — the dependency manifest opencode uses for local
/// plugins and custom tools. opencode runs `bun install` in this directory at
/// startup, so an entry here is what makes `import { x } from "pkg"` resolve.
@MainActor
final class DependencyStore: ObservableObject {
    @Published private(set) var base: URL
    @Published private(set) var document: [String: Any] = [:]
    @Published private(set) var packages: [PackageDependency] = []
    @Published private(set) var exists = false
    @Published private(set) var loadError: String?
    @Published private(set) var nodeModulesPresent = false
    @Published private(set) var installedCount = 0
    @Published private(set) var lockfileName: String?
    @Published private(set) var modifiedAt: Date?

    init(base: URL = Paths.configDir) {
        self.base = base
        reload()
    }

    var fileURL: URL { base.appendingPathComponent("package.json") }
    var nodeModules: URL { base.appendingPathComponent("node_modules", isDirectory: true) }

    private var lockfileCandidates: [String] {
        ["bun.lock", "bun.lockb", "package-lock.json", "pnpm-lock.yaml", "yarn.lock"]
    }

    // MARK: - Load

    func load(base newBase: URL? = nil) {
        if let newBase { base = newBase }
        reload()
    }

    func reload() {
        loadError = nil
        exists = FS.exists(fileURL)
        document = [:]

        if exists {
            do {
                let data = try Data(contentsOf: fileURL)
                let any = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
                guard let object = any as? [String: Any] else {
                    throw HubError.invalidInput("package.json must contain a JSON object.")
                }
                document = object
            } catch {
                loadError = "package.json could not be parsed: \(error.localizedDescription)"
            }
        }
        refreshDerived()
    }

    private func refreshDerived() {
        var rows: [PackageDependency] = []
        for section in DependencySection.allCases {
            for (name, requirement) in Self.map(document[section.rawValue]) {
                rows.append(PackageDependency(name: name, requirement: requirement, section: section))
            }
        }
        packages = rows.sorted { lhs, rhs in
            if lhs.section != rhs.section { return lhs.section.rawValue < rhs.section.rawValue }
            return lhs.name < rhs.name
        }
        nodeModulesPresent = FS.isDirectory(nodeModules)
        installedCount = nodeModulesPresent ? FS.children(nodeModules).filter { !$0.lastPathComponent.hasPrefix(".") }.count : 0
        lockfileName = lockfileCandidates.first { FS.exists(base.appendingPathComponent($0)) }
        modifiedAt = FS.modified(fileURL)
    }

    private static func map(_ value: Any?) -> [String: String] {
        guard let dict = value as? [String: Any] else { return [:] }
        var result: [String: String] = [:]
        for (key, raw) in dict {
            if let text = raw as? String { result[key] = text }
        }
        return result
    }

    // MARK: - Mutate

    func add(name: String, requirement: String, section: DependencySection) throws {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidName(cleanedName) else {
            throw HubError.invalidInput("“\(cleanedName)” is not a valid npm package name (lowercase letters, digits, . - _ and an optional @scope/).")
        }
        let cleanedRequirement = requirement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidRequirement(cleanedRequirement) else {
            throw HubError.invalidInput("“\(cleanedRequirement)” is not a version range. Use latest, 1.2.3, ^1.2.3, ~1.2, >=1.2 <2, or a file: path.")
        }

        var next = document
        for other in DependencySection.allCases where other != section {
            var map = Self.map(next[other.rawValue])
            map.removeValue(forKey: cleanedName)
            if map.isEmpty { next.removeValue(forKey: other.rawValue) } else { next[other.rawValue] = map }
        }
        var map = Self.map(next[section.rawValue])
        map[cleanedName] = cleanedRequirement.isEmpty ? "latest" : cleanedRequirement
        next[section.rawValue] = map
        try commit(next)
    }

    func remove(_ dependency: PackageDependency) throws {
        var next = document
        var map = Self.map(next[dependency.section.rawValue])
        map.removeValue(forKey: dependency.name)
        if map.isEmpty { next.removeValue(forKey: dependency.section.rawValue) } else { next[dependency.section.rawValue] = map }
        try commit(next)
    }

    func setRequirement(_ dependency: PackageDependency, to requirement: String) throws {
        try add(name: dependency.name, requirement: requirement, section: dependency.section)
    }

    /// Promotes every dependency that still says "latest" to an exact caret range
    /// resolved from npm. Returns the names that changed.
    func pinResolved(_ resolved: [String: String]) throws -> [String] {
        var next = document
        var changed: [String] = []
        for section in DependencySection.allCases {
            var map = Self.map(next[section.rawValue])
            for (name, requirement) in map where requirement == "latest" || requirement == "*" {
                guard let version = resolved[name], !version.isEmpty else { continue }
                map[name] = "^" + version
                changed.append(name)
            }
            if !map.isEmpty { next[section.rawValue] = map }
        }
        guard !changed.isEmpty else { return [] }
        try commit(next)
        return changed
    }

    func clearDependencies() throws {
        var next = document
        for section in DependencySection.allCases { next.removeValue(forKey: section.rawValue) }
        try commit(next)
    }

    private func commit(_ next: [String: Any]) throws {
        var output = next
        if output["name"] == nil { output["name"] = "opencode-config" }
        if output["private"] == nil { output["private"] = true }

        let data = try JSONSerialization.data(
            withJSONObject: output,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        var terminated = data
        terminated.append(0x0A)

        try FS.ensure(base)
        _ = try FS.backup(fileURL)
        try FS.atomicWrite(terminated, to: fileURL)

        document = output
        exists = true
        loadError = nil
        refreshDerived()
    }

    // MARK: - Validation

    static func isValidName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 214 else { return false }
        let pattern = #"^(@[a-z0-9][a-z0-9._-]*/)?[a-z0-9][a-z0-9._-]*$"#
        return name.range(of: pattern, options: .regularExpression) != nil
    }

    static func isValidRequirement(_ requirement: String) -> Bool {
        if requirement.isEmpty { return true }
        guard requirement.count <= 96 else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_^~<>=|*/ @:+")
        return requirement.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    var summary: String {
        if loadError != nil { return "package.json is invalid" }
        if !exists { return "No package.json yet" }
        if packages.isEmpty { return "package.json declares no packages" }
        let runtime = packages.filter { $0.section == .dependencies }.count
        let development = packages.count - runtime
        return "\(runtime) runtime · \(development) development"
    }
}
