import Foundation

struct NpmPackage: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let version: String
    let summary: String
    let homepage: String?
    let author: String?
    let keywords: [String]
}

enum HTTP {
    static func data(
        _ urlString: String,
        headers: [String: String] = [:],
        timeout: TimeInterval = 25
    ) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw HubError.invalidInput("Not a valid URL: \(urlString)")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("OpenCodeHub/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(decoding: data.prefix(400), as: UTF8.self)
            throw HubError.invalidInput("HTTP \(http.statusCode) from \(url.host ?? urlString).\n\(body)")
        }
        return data
    }

    static func json(_ urlString: String, headers: [String: String] = [:]) async throws -> Any {
        let data = try await data(urlString, headers: headers)
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    static func text(_ urlString: String, headers: [String: String] = [:]) async throws -> String {
        String(decoding: try await data(urlString, headers: headers), as: UTF8.self)
    }
}

enum NPMRegistry {
    /// Percent-escapes the slash in scoped names: @scope/name -> @scope%2Fname
    static func endpoint(_ name: String) -> String {
        "https://registry.npmjs.org/\(name.replacingOccurrences(of: "/", with: "%2F"))"
    }

    static func info(_ name: String) async throws -> NpmPackage {
        let json = try await HTTP.json(endpoint(name))
        guard let root = json as? [String: Any] else {
            throw HubError.invalidInput("\(name) is not an npm package.")
        }
        let distTags = (root["dist-tags"] as? [String: Any]) ?? [:]
        let latest = (distTags["latest"] as? String) ?? ""
        let versions = (root["versions"] as? [String: Any]) ?? [:]
        let entry = (versions[latest] as? [String: Any]) ?? [:]
        let description = (entry["description"] as? String) ?? (root["description"] as? String) ?? ""
        let homepage = (entry["homepage"] as? String) ?? (root["homepage"] as? String)
        var author: String?
        if let raw = root["author"] as? [String: Any] { author = raw["name"] as? String }
        else if let raw = root["author"] as? String { author = raw }
        return NpmPackage(
            name: (root["name"] as? String) ?? name,
            version: latest,
            summary: description,
            homepage: homepage,
            author: author,
            keywords: (entry["keywords"] as? [String]) ?? []
        )
    }

    static func versions(_ name: String) async throws -> [String] {
        let json = try await HTTP.json(endpoint(name))
        guard let root = json as? [String: Any], let versions = root["versions"] as? [String: Any] else {
            return []
        }
        return versions.keys.sorted { lhs, rhs in
            lhs.compare(rhs, options: .numeric) == .orderedDescending
        }
    }

    static func search(_ query: String, size: Int = 25) async throws -> [NpmPackage] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        let url = "https://registry.npmjs.org/-/v1/search?text=\(encoded)&size=\(size)"
        let json = try await HTTP.json(url)
        guard let root = json as? [String: Any], let objects = root["objects"] as? [[String: Any]] else {
            return []
        }
        return objects.compactMap { object in
            guard let pkg = object["package"] as? [String: Any], let name = pkg["name"] as? String else { return nil }
            var author: String?
            if let raw = pkg["author"] as? [String: Any] { author = raw["name"] as? String }
            else if let raw = pkg["author"] as? String { author = raw }
            return NpmPackage(
                name: name,
                version: (pkg["version"] as? String) ?? "",
                summary: (pkg["description"] as? String) ?? "",
                homepage: ((pkg["links"] as? [String: Any])?["homepage"] as? String),
                author: author,
                keywords: (pkg["keywords"] as? [String]) ?? []
            )
        }
    }
}

struct GitHubSource: Hashable {
    let owner: String
    let repo: String
    let ref: String?
    let subpath: String?

    var slug: String { "\(owner)/\(repo)" }
    var display: String { subpath.map { "\(slug)/\($0)" } ?? slug }

    /// Accepts `owner/repo`, `owner/repo/sub/dir`, `owner/repo@ref`,
    /// and https://github.com/owner/repo/tree/ref/sub/dir URLs.
    static func parse(_ raw: String) -> GitHubSource? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if text.hasPrefix("http://") || text.hasPrefix("https://") {
            guard let url = URL(string: text) else { return nil }
            let parts = url.path.split(separator: "/").map(String.init)
            guard parts.count >= 2 else { return nil }
            let owner = parts[0]
            let repo = parts[1].replacingOccurrences(of: ".git", with: "")
            if parts.count >= 4, parts[2] == "tree" || parts[2] == "blob" {
                let ref = parts[3]
                let rest = parts.dropFirst(4).joined(separator: "/")
                return GitHubSource(owner: owner, repo: repo, ref: ref, subpath: rest.isEmpty ? nil : rest)
            }
            return GitHubSource(owner: owner, repo: repo, ref: nil, subpath: nil)
        }

        var ref: String?
        if let at = text.lastIndex(of: "@"), at > text.startIndex {
            let candidate = String(text[text.index(after: at)...])
            text = String(text[text.startIndex..<at])
            ref = candidate.isEmpty ? nil : candidate
        }

        let parts = text.split(separator: "/").map(String.init).filter { !$0.isEmpty }
        guard parts.count >= 2 else { return nil }
        let owner = parts[0]
        let repo = parts[1].replacingOccurrences(of: ".git", with: "")
        let rest = parts.dropFirst(2).joined(separator: "/")
        guard !owner.isEmpty, !repo.isEmpty else { return nil }
        return GitHubSource(owner: owner, repo: repo, ref: ref, subpath: rest.isEmpty ? nil : rest)
    }

    var tarballURL: String {
        "https://codeload.github.com/\(owner)/\(repo)/tar.gz/\(ref ?? "HEAD")"
    }

    func rawURL(_ path: String) -> String {
        "https://raw.githubusercontent.com/\(owner)/\(repo)/\(ref ?? "HEAD")/\(path)"
    }
}
