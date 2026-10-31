import SwiftUI

@MainActor
struct DashboardView: View {
    @EnvironmentObject private var workspace: Workspace
    @Binding var selection: HubSection?
    @State private var quickSpec = ""
    @State private var lookup: NpmPackage?
    @State private var lookingUp = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero
                stats
                HStack(alignment: .top, spacing: 16) {
                    environmentCard
                    locationsCard
                }
                quickInstallCard
                if !workspace.installedCatalogIDs.isEmpty {
                    installedCard
                }
            }
            .padding(20)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("OpenCode Hub")
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text("Install plugins, agent skills, custom tools and MCP servers into opencode — with a backup of every file it touches.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button {
                    selection = .catalog
                } label: {
                    Label("Browse catalog", systemImage: "shippingbox")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    workspace.chooseProject()
                } label: {
                    Label(workspace.projectRoot == nil ? "Choose project folder" : "Change project folder",
                          systemImage: "folder")
                }

                Button {
                    workspace.refresh()
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
            }
            .padding(.top, 6)
        }
    }

    private var stats: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            StatCard(title: "Plugins", value: "\(workspace.npmPlugins.count + workspace.allLocalPlugins.count)",
                     symbol: "puzzlepiece.extension", tint: .purple)
            StatCard(title: "Skills", value: "\(workspace.allSkills.count)",
                     symbol: "book.closed", tint: .blue)
            StatCard(title: "Tools", value: "\(workspace.allTools.count)",
                     symbol: "wrench.and.screwdriver", tint: .orange)
            StatCard(title: "MCP servers", value: "\(workspace.servers.count)",
                     symbol: "antenna.radiowaves.left.and.right", tint: .green)
            StatCard(title: "Packages", value: "\(workspace.dependencies.packages.count)",
                     symbol: "shippingbox", tint: .indigo)
        }
    }

    private var environmentCard: some View {
        SectionCard(title: "Environment", subtitle: "Checked \(workspace.lastRefresh.formatted(date: .omitted, time: .shortened))") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(workspace.health) { item in
                    HealthRow(item: item)
                }
                Divider()
                Button {
                    Task { await workspace.cli.refresh() }
                } label: {
                    Label("Re-check", systemImage: "stethoscope")
                }
                .buttonStyle(.link)
                .font(.callout)
            }
        }
    }

    private var locationsCard: some View {
        SectionCard(title: "Locations") {
            VStack(alignment: .leading, spacing: 12) {
                PathRow(title: "opencode.json", url: workspace.config.url) {
                    workspace.reveal(workspace.config.url)
                }
                PathRow(title: "Global plugins", url: Paths.globalPluginsDir) {
                    workspace.reveal(Paths.globalPluginsDir)
                }
                PathRow(title: "Global skills", url: Paths.globalSkillsDir) {
                    workspace.reveal(Paths.globalSkillsDir)
                }
                PathRow(title: "Global tools", url: Paths.globalToolsDir) {
                    workspace.reveal(Paths.globalToolsDir)
                }
                PathRow(title: "Plugin cache", url: Paths.nodeModulesCache) {
                    workspace.reveal(Paths.cacheDir)
                }
                if let project = workspace.projectRoot {
                    Divider()
                    Text("Project: \(Paths.tilde(project))").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var quickInstallCard: some View {
        SectionCard(title: "Quick install a plugin", subtitle: "Any npm package that exports an opencode plugin") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    TextField("opencode-wakatime or @scope/plugin@1.2.0", text: $quickSpec)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { add() }
                    Button("Add") { add() }
                        .buttonStyle(.borderedProminent)
                        .disabled(quickSpec.trimmingCharacters(in: .whitespaces).isEmpty || workspace.busy != nil)
                    Button {
                        Task { await performLookup() }
                    } label: {
                        if lookingUp { ProgressView().controlSize(.small) } else { Text("Look up") }
                    }
                    .disabled(quickSpec.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let lookup {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(lookup.name).font(.callout.weight(.medium))
                            Pill(text: "v\(lookup.version)", tint: .blue)
                        }
                        Text(lookup.summary.isEmpty ? "No description published." : lookup.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                } else {
                    Text("Plugins are installed by opencode with Bun on the next start, or immediately with Prefetch in the Plugins tab.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var installedCard: some View {
        SectionCard(title: "From the catalog", subtitle: "\(workspace.installedCatalogIDs.count) installed") {
            FlowRow(items: workspace.catalog.filter { workspace.installedCatalogIDs.contains($0.id) }) { entry in
                Pill(text: entry.name, tint: .green)
            }
        }
    }

    private func add() {
        let spec = quickSpec
        guard !spec.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        quickSpec = ""
        Task { await workspace.perform("Adding \(spec)") { try await workspace.installPlugin(spec, scope: .global) } }
    }

    private func performLookup() async {
        lookingUp = true
        defer { lookingUp = false }
        let name = NpmPlugin(spec: quickSpec).name
        lookup = try? await NPMRegistry.info(name)
        if lookup == nil {
            workspace.errorMessage = "npm has no package named \(name)."
        }
    }
}

/// Tiny wrapping row used for tag clouds.
@MainActor
struct FlowRow<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let content: (Item) -> Content

    init(items: [Item], @ViewBuilder content: @escaping (Item) -> Content) {
        self.items = items
        self.content = content
    }

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 110), spacing: 6)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(items) { item in
                content(item)
            }
        }
    }
}
