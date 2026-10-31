import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct PluginsView: View {
    @EnvironmentObject private var workspace: Workspace
    @State private var newSpec = ""
    @State private var pinTarget: NpmPlugin?
    @State private var pinVersion = ""
    @State private var showImporter = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                addCard
                npmCard
                localCard
                if !workspace.npmPlugins.isEmpty {
                    prefetchCard
                }
            }
            .padding(20)
        }
        .sheet(item: $pinTarget) { plugin in
            pinSheet(plugin)
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.javascript, .plainText, .sourceCode, .data],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { await workspace.addLocalPlugin(from: url) }
            case .failure(let error):
                workspace.errorMessage = error.localizedDescription
            }
        }
    }

    private var addCard: some View {
        SectionCard(title: "Add an npm plugin",
                    subtitle: "Writes into the plugin array of opencode.json. opencode installs the package with Bun at startup.") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    TextField("opencode-wakatime", text: $newSpec)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { add() }
                    Button("Add plugin") { add() }
                        .buttonStyle(.borderedProminent)
                        .disabled(newSpec.trimmingCharacters(in: .whitespaces).isEmpty || workspace.busy != nil)
                }
                Text(workspace.settings.installPluginsWithCLI
                     ? "The CLI path is on: `opencode plugin <name>` runs and writes the entry itself."
                     : "Direct config path: the entry is added immediately, no CLI required.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var npmCard: some View {
        SectionCard(title: "Declared plugins", subtitle: "\(workspace.npmPlugins.count) in opencode.json") {
            if workspace.npmPlugins.isEmpty {
                EmptyStateView(symbol: "puzzlepiece.extension", title: "No npm plugins",
                               message: "Add a package above, or pick one from the catalog.")
            } else {
                VStack(spacing: 0) {
                    ForEach(workspace.npmPlugins) { plugin in
                        HStack(spacing: 10) {
                            Image(systemName: "puzzlepiece.extension")
                                .foregroundStyle(.purple)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(plugin.name).font(.callout.weight(.medium))
                                Text(plugin.version == nil ? "tracks latest" : "pinned to \(plugin.version!)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Pill(text: plugin.versionText, tint: plugin.version == nil ? .secondary : .blue)
                            Menu {
                                Button("Use latest") { workspace.pin(plugin, version: nil) }
                                Button("Pin version…") {
                                    pinVersion = plugin.version ?? ""
                                    pinTarget = plugin
                                }
                                Divider()
                                Button("Copy spec") { workspace.copyToPasteboard(plugin.spec) }
                                Button("Remove", role: .destructive) { workspace.removePlugin(plugin) }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                            .menuStyle(.borderlessButton)
                            .frame(width: 26)
                        }
                        .padding(.vertical, 8)
                        if plugin.id != workspace.npmPlugins.last?.id { Divider() }
                    }
                }
            }
        }
    }

    private var localCard: some View {
        SectionCard(title: "Local plugin files",
                    subtitle: "Files in the plugins/ folder load automatically and need no config entry.") {
            VStack(alignment: .leading, spacing: 10) {
                if workspace.allLocalPlugins.isEmpty {
                    EmptyStateView(symbol: "doc.badge.plus", title: "No local plugins",
                                   message: "Drop a .ts or .js file into ~/.config/opencode/plugins to load it at startup.")
                } else {
                    VStack(spacing: 0) {
                        ForEach(workspace.allLocalPlugins) { plugin in
                            HStack(spacing: 10) {
                                Image(systemName: plugin.symbol).foregroundStyle(.orange).frame(width: 18)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(plugin.fileName).font(.callout.weight(.medium))
                                    Text("\(plugin.scope.rawValue) · \(FS.prettySize(plugin.size))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Reveal") { workspace.reveal(plugin.url) }
                                    .buttonStyle(.link)
                                Button(role: .destructive) {
                                    workspace.deleteLocalPlugin(plugin)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(.vertical, 7)
                            if plugin.id != workspace.allLocalPlugins.last?.id { Divider() }
                        }
                    }
                }
                HStack {
                    Button {
                        showImporter = true
                    } label: {
                        Label("Add file…", systemImage: "plus")
                    }
                    Button {
                        workspace.openFolder(Paths.globalPluginsDir)
                    } label: {
                        Label("Open plugins folder", systemImage: "folder")
                    }
                    Spacer()
                }
            }
        }
    }

    private var prefetchCard: some View {
        SectionCard(title: "Install now", subtitle: "opencode installs plugins on start. Prefetching warms ~/.cache/opencode/node_modules.") {
            HStack(spacing: 10) {
                Button {
                    Task { await workspace.prefetchAllPlugins() }
                } label: {
                    Label("Prefetch \(workspace.npmPlugins.count) plugins with Bun", systemImage: "arrow.down.circle")
                }
                .disabled(workspace.busy != nil)
                Spacer()
                Button {
                    workspace.reveal(Paths.cacheDir)
                } label: {
                    Label("Reveal cache", systemImage: "folder")
                }
            }
        }
    }

    private func pinSheet(_ plugin: NpmPlugin) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Pin \(plugin.name)").font(.headline)
            TextField("1.2.3 or a dist-tag like beta", text: $pinVersion)
                .textFieldStyle(.roundedBorder)
            Text("Leave empty to follow the latest published version.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { pinTarget = nil }
                Button("Save") {
                    let version = pinVersion.trimmingCharacters(in: .whitespaces)
                    workspace.pin(plugin, version: version.isEmpty ? nil : version)
                    pinTarget = nil
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func add() {
        let spec = newSpec.trimmingCharacters(in: .whitespaces)
        guard !spec.isEmpty else { return }
        newSpec = ""
        Task { await workspace.perform("Adding \(spec)") { try await workspace.installPlugin(spec, scope: .global) } }
    }
}
