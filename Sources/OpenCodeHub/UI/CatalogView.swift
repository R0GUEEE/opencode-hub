import SwiftUI

@MainActor
struct CatalogView: View {
    @EnvironmentObject private var workspace: Workspace
    @State private var kind: InstallKind?
    @State private var query = ""
    @State private var scope: Skill.Scope = .global
    @State private var npmResults: [CatalogEntry] = []
    @State private var searching = false

    private var entries: [CatalogEntry] {
        var base = workspace.catalog
        if let kind { base = base.filter { $0.kind == kind } }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            base = base.filter {
                $0.name.localizedCaseInsensitiveContains(trimmed)
                    || $0.summary.localizedCaseInsensitiveContains(trimmed)
                    || $0.source.localizedCaseInsensitiveContains(trimmed)
                    || $0.tags.contains { $0.localizedCaseInsensitiveContains(trimmed) }
            }
        }
        return base
    }

    private var installed: Set<String> { workspace.installedCatalogIDs }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !npmResults.isEmpty {
                        sectionTitle("npm results for “\(query)”")
                        grid(npmResults, isNpm: true)
                    }
                    if entries.isEmpty && npmResults.isEmpty {
                        EmptyStateView(symbol: "shippingbox", title: "Nothing matches",
                                       message: "Try another word, or search npm for a plugin package.")
                    } else {
                        if !npmResults.isEmpty { sectionTitle("Catalog") }
                        grid(entries, isNpm: false)
                    }
                }
                .padding(20)
            }
        }
        .searchable(text: $query, prompt: "Search catalog")
    }

    private var header: some View {
        HStack(spacing: 12) {
            Picker("Kind", selection: $kind) {
                Text("All").tag(InstallKind?.none)
                ForEach(InstallKind.allCases) { kind in
                    Text(kind.plural).tag(InstallKind?.some(kind))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 420)

            Spacer()

            Picker("Scope", selection: $scope) {
                Text("Global").tag(Skill.Scope.global)
                Text("Project").tag(Skill.Scope.project)
            }
            .pickerStyle(.menu)
            .frame(width: 140)

            Button {
                Task { await searchNpm() }
            } label: {
                if searching { ProgressView().controlSize(.small) }
                else { Label("Search npm", systemImage: "magnifyingglass") }
            }
            .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || searching)

            Button {
                Task { await workspace.loadRemoteCatalog() }
            } label: {
                Label("Remote catalog", systemImage: "arrow.down.circle")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
    }

    private func grid(_ items: [CatalogEntry], isNpm: Bool) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 310), spacing: 12)], alignment: .leading, spacing: 12) {
            ForEach(items) { entry in
                CatalogCard(entry: entry, installed: installed.contains(entry.id) || isNpmInstalled(entry)) {
                    Task { await workspace.install(entry, scope: scope) }
                }
            }
        }
    }

    private func isNpmInstalled(_ entry: CatalogEntry) -> Bool {
        workspace.npmPlugins.contains { $0.name == NpmPlugin(spec: entry.source).name }
    }

    private func searchNpm() async {
        searching = true
        defer { searching = false }
        do {
            npmResults = try await Catalog.searchPlugins(query)
            if npmResults.isEmpty {
                workspace.notice = "npm returned no packages for “\(query)”"
            }
        } catch {
            workspace.errorMessage = error.localizedDescription
        }
    }
}

@MainActor
struct CatalogCard: View {
    let entry: CatalogEntry
    let installed: Bool
    let install: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.name).font(.headline).lineLimit(1)
                    HStack(spacing: 5) {
                        Pill(text: entry.kind.title, tint: tint)
                        if let version = entry.version { Pill(text: version, tint: .secondary) }
                        if entry.verified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption2)
                                .foregroundStyle(.green)
                                .help("Curated entry")
                        }
                    }
                }
                Spacer()
                Button(action: install) {
                    Image(systemName: installed ? "checkmark.circle.fill" : "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(installed ? Color.green : Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(installed)
                .help(installed ? "Already installed" : "Install \(entry.name)")
            }

            Text(entry.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 2)

            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch").font(.caption2)
                Text(entry.source).font(.caption.monospaced()).lineLimit(1)
                Spacer()
                if let author = entry.author {
                    Text(author).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(installed ? Color.green.opacity(0.35) : Color.primary.opacity(0.07)))
    }

    private var tint: Color {
        switch entry.kind {
        case .plugin: return .purple
        case .skill: return .blue
        case .tool: return .orange
        case .mcp: return .green
        }
    }
}
