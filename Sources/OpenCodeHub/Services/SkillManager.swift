import Foundation

struct Frontmatter {
    var fields: [String: String]
    var body: String

    var name: String? { fields["name"] }
    var summary: String? { fields["description"] }
    var license: String? { fields["license"] }
}

enum SkillManager {
    static let skillFile = "SKILL.md"

    // MARK: - Discovery

    static func installed(scope: Skill.Scope, base: URL) -> [Skill] {
        guard FS.isDirectory(base) else { return [] }
        var result: [Skill] = []
        for child in FS.children(base) where FS.isDirectory(child) {
            let manifest = child.appendingPathComponent(skillFile)
            guard FS.exists(manifest), let text = FS.read(manifest) else { continue }
            let meta = parseFrontmatter(text)
            result.append(Skill(
                slug: child.lastPathComponent,
                name: meta.name ?? child.lastPathComponent,
                summary: meta.summary ?? "",
                path: child,
                fileCount: FS.fileCount(child),
                modified: FS.modified(child),
                scope: scope,
                license: meta.license
            ))
        }
        return result.sorted { $0.slug.localizedStandardCompare($1.slug) == .orderedAscending }
    }

    // MARK: - Frontmatter

    static func parseFrontmatter(_ text: String) -> Frontmatter {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" else {
            return Frontmatter(fields: [:], body: normalized)
        }

        var fields: [String: String] = [:]
        var index = 1
        var currentKey: String?
        var buffer: [String] = []

        func flush() {
            if let key = currentKey {
                fields[key] = unquote(buffer.joined(separator: " ").trimmed)
            }
            currentKey = nil
            buffer = []
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed == "---" || trimmed == "..." {
                flush()
                let body = index + 1 < lines.count ? lines[(index + 1)...].joined(separator: "\n") : ""
                return Frontmatter(fields: fields, body: body)
            }

            let isIndented = line.hasPrefix(" ") || line.hasPrefix("\t")
            if let colon = line.firstIndex(of: ":"), !isIndented {
                flush()
                let key = String(line[line.startIndex..<colon]).trimmed.lowercased()
                var value = String(line[line.index(after: colon)...]).trimmed
                if value == ">" || value == "|" || value == ">-" || value == "|-" { value = "" }
                currentKey = key
                buffer = value.isEmpty ? [] : [value]
            } else if currentKey != nil {
                let content = line.trimmingCharacters(in: .whitespaces)
                if !content.isEmpty { buffer.append(content) }
            }
            index += 1
        }

        flush()
        return Frontmatter(fields: fields, body: normalized)
    }

    private static func unquote(_ value: String) -> String {
        var text = value
        if text.count >= 2, (text.hasPrefix("\"") && text.hasSuffix("\"")) || (text.hasPrefix("'") && text.hasSuffix("'")) {
            text.removeFirst()
            text.removeLast()
        }
        return text.replacingOccurrences(of: "\\n", with: " ")
    }

    // MARK: - Install

    static func destination(for slug: String, scope: Skill.Scope, projectRoot: URL?) throws -> URL {
        let base: URL
        switch scope {
        case .global: base = Paths.globalSkillsDir
        case .project:
            guard let projectRoot else { throw HubError.invalidInput("Pick a project folder first.") }
            base = Paths.projectSkillsDir(projectRoot)
        }
        try FS.ensure(base)
        return base.appendingPathComponent(slug, isDirectory: true)
    }

    static func slugify(_ raw: String) -> String {
        let lowered = raw.lowercased()
        var out = ""
        var lastDash = false
        for character in lowered {
            if character.isLetter || character.isNumber {
                out.append(character)
                lastDash = false
            } else if !lastDash {
                out.append("-")
                lastDash = true
            }
        }
        let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "skill-\(Int(Date().timeIntervalSince1970))" : String(trimmed.prefix(64))
    }

    static func installFromGitHub(
        _ raw: String,
        scope: Skill.Scope,
        projectRoot: URL?,
        log: @escaping @Sendable (String) -> Void
    ) async throws -> Skill {
        guard let source = GitHubSource.parse(raw) else {
            throw HubError.invalidInput("Expected owner/repo or a github.com URL. Got: \(raw)")
        }
        log("Resolving \(source.display)")
        let archive = try await HTTP.data(source.tarballURL, timeout: 90)
        log("Downloaded \(FS.prettySize(Int64(archive.count))) archive")

        let work = try FS.makeTemp("skill")
        defer { try? FileManager.default.removeItem(at: work) }
        let archiveURL = work.appendingPathComponent("source.tar.gz")
        try archive.write(to: archiveURL)

        let unpack = work.appendingPathComponent("unpack", isDirectory: true)
        try FS.ensure(unpack)
        let result = try await Shell.run("/usr/bin/tar", ["-xzf", archiveURL.path, "-C", unpack.path], timeout: 90)
        guard result.succeeded else { throw ShellError.failed(result) }

        let root = try repositoryRoot(in: unpack)
        let candidateRoot: URL
        if let subpath = source.subpath, !subpath.isEmpty {
            guard let target = FS.safeJoin(root, subpath) else {
                throw HubError.invalidInput("Subpath \(subpath) escapes the repository.")
            }
            candidateRoot = target
        } else {
            candidateRoot = root
        }

        guard let skillDirectory = findSkillDirectory(startingAt: candidateRoot, depth: 4) else {
            throw HubError.invalidInput("No SKILL.md found in \(source.display).")
        }
        return try installDirectory(skillDirectory, scope: scope, projectRoot: projectRoot, log: log)
    }

    static func installDirectory(
        _ directory: URL,
        scope: Skill.Scope,
        projectRoot: URL?,
        log: @escaping @Sendable (String) -> Void
    ) throws -> Skill {
        let manifest = directory.appendingPathComponent(skillFile)
        guard let text = FS.read(manifest) else {
            throw HubError.invalidInput("\(directory.lastPathComponent) has no SKILL.md at its root.")
        }
        let meta = parseFrontmatter(text)
        guard let description = meta.summary, !description.isEmpty else {
            throw HubError.invalidInput("SKILL.md needs a non-empty `description` field in its frontmatter.")
        }
        let slug = slugify(meta.name ?? directory.lastPathComponent)
        let destination = try destination(for: slug, scope: scope, projectRoot: projectRoot)
        if FS.exists(destination) {
            log("Replacing existing skill \(slug)")
            try FS.trash(destination)
        }
        try FileManager.default.copyItem(at: directory, to: destination)
        log("Installed \(slug) to \(Paths.tilde(destination))")
        return Skill(
            slug: slug,
            name: meta.name ?? slug,
            summary: description,
            path: destination,
            fileCount: FS.fileCount(destination),
            modified: Date(),
            scope: scope,
            license: meta.license
        )
    }

    static func installFromRemoteFile(
        _ urlString: String,
        scope: Skill.Scope,
        projectRoot: URL?,
        log: @escaping @Sendable (String) -> Void
    ) async throws -> Skill {
        if let source = GitHubSource.parse(urlString), !urlString.lowercased().hasSuffix(".md") {
            return try await installFromGitHub(urlString, scope: scope, projectRoot: projectRoot, log: log)
        }
        log("Downloading \(urlString)")
        let text = try await HTTP.text(urlString, timeout: 60)
        let meta = parseFrontmatter(text)
        guard let description = meta.summary, !description.isEmpty else {
            throw HubError.invalidInput("That file has no frontmatter `description`, so it is not an Agent Skill.")
        }
        let base = urlString.split(separator: "/").last.map(String.init) ?? "skill.md"
        let fallback = (base as NSString).deletingPathExtension
        let slug = slugify(meta.name ?? fallback)
        let destination = try destination(for: slug, scope: scope, projectRoot: projectRoot)
        try FS.ensure(destination)
        try FS.atomicWrite(text, to: destination.appendingPathComponent(skillFile))
        log("Installed \(slug) to \(Paths.tilde(destination))")
        return Skill(
            slug: slug,
            name: meta.name ?? slug,
            summary: description,
            path: destination,
            fileCount: 1,
            modified: Date(),
            scope: scope,
            license: meta.license
        )
    }

    static func uninstall(_ skill: Skill) throws {
        let target = skill.path
        if FS.isDirectory(target) {
            try FS.trash(target)
        } else {
            let manifest = target.appendingPathComponent("SKILL.md")
            if FS.exists(manifest) { try FS.trash(manifest) } else { try FS.trash(target) }
        }
    }

    // MARK: - Helpers

    private static func repositoryRoot(in unpacked: URL) throws -> URL {
        let children = FS.children(unpacked).filter { FS.isDirectory($0) }
        if children.count == 1 { return children[0] }
        if let direct = children.first(where: { FS.exists($0.appendingPathComponent(skillFile)) }) { return direct }
        return unpacked
    }

    private static func findSkillDirectory(startingAt root: URL, depth: Int) -> URL? {
        if FS.exists(root.appendingPathComponent(skillFile)) { return root }
        guard depth > 0 else { return nil }
        for child in FS.children(root) where FS.isDirectory(child) {
            if child.lastPathComponent.hasPrefix(".") { continue }
            if child.lastPathComponent == "node_modules" { continue }
            if let found = findSkillDirectory(startingAt: child, depth: depth - 1) { return found }
        }
        return nil
    }
}
