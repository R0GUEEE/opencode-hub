import SwiftUI

@MainActor
struct SettingsView: View {
    @EnvironmentObject private var workspace: Workspace
    @EnvironmentObject private var settings: HubSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionCard(title: "Install behaviour") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Install npm plugins with the opencode CLI", isOn: $settings.installPluginsWithCLI)
                        Text("Runs `opencode plugin <package>`, which updates the config itself. With this off the hub edits opencode.json directly.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Toggle("Prefetch plugin packages with Bun after adding", isOn: $settings.prefetchAfterInstall)
                            .disabled(!(workspace.cli.bun?.isPresent ?? false))
                        Text(workspace.cli.bun?.isPresent == true
                             ? "Runs `bun add` in ~/.cache/opencode so the first opencode start is instant."
                             : "Bun is not installed, so prefetching is unavailable.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Toggle("Show project-scoped entries", isOn: $settings.showProjectScope)
                    }
                }

                SectionCard(title: "Project folder",
                            subtitle: "Used for .opencode/plugins, skills and tools") {
                    HStack(spacing: 10) {
                        Text(workspace.projectRoot.map { Paths.tilde($0) } ?? "None")
                            .font(.callout.monospaced())
                            .lineLimit(1)
                            .foregroundStyle(workspace.projectRoot == nil ? .secondary : .primary)
                        Spacer()
                        Button("Choose…") { workspace.chooseProject() }
                        Button("Clear") { workspace.clearProject() }
                            .disabled(workspace.projectRoot == nil)
                    }
                }

                SectionCard(title: "Catalog",
                            subtitle: "Remote catalogs are JSON arrays of entries, merged over the bundled set") {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("https://example.com/opencode-catalog.json", text: $settings.remoteCatalogURL)
                            .textFieldStyle(.roundedBorder)
                        HStack {
                            Button("Load now") {
                                Task { await workspace.loadRemoteCatalog() }
                            }
                            .disabled(settings.remoteCatalogURL.trimmingCharacters(in: .whitespaces).isEmpty)
                            Button("Reset to bundled") { workspace.resetCatalog() }
                            Spacer()
                            Text("\(workspace.catalog.count) entries").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                SectionCard(title: "Binaries") {
                    VStack(alignment: .leading, spacing: 6) {
                        binaryRow("opencode", path: workspace.cli.opencodePath, version: workspace.cli.opencodeVersion)
                        binaryRow("bun", path: workspace.cli.bun?.path, version: workspace.cli.bun?.version)
                        binaryRow("node", path: workspace.cli.node?.path, version: workspace.cli.node?.version)
                        binaryRow("npm", path: workspace.cli.npm?.path, version: workspace.cli.npm?.version)
                        binaryRow("git", path: workspace.cli.git?.path, version: workspace.cli.git?.version)
                        Divider().padding(.vertical, 4)
                        HStack {
                            Text("GUI apps do not inherit your shell PATH; the hub searches /opt/homebrew/bin, /usr/local/bin, ~/.opencode/bin and ~/.bun/bin.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Re-check") { Task { await workspace.cli.refresh() } }
                        }
                    }
                }

                SectionCard(title: "Files") {
                    VStack(alignment: .leading, spacing: 10) {
                        PathRow(title: "opencode.json", url: workspace.config.url) {
                            workspace.reveal(workspace.config.url)
                        }
                        PathRow(title: "Config folder", url: Paths.configDir) {
                            workspace.reveal(Paths.configDir)
                        }
                        PathRow(title: "Backups", url: Paths.backupsDir) {
                            workspace.revealBackups()
                        }
                        PathRow(title: "Hub log", url: Paths.appLogFile) {
                            workspace.reveal(Paths.appLogFile)
                        }
                        HStack {
                            Button("Open in editor") { workspace.openConfig() }
                            Button("Reload from disk") { workspace.reloadConfig() }
                            if !workspace.config.fileExists {
                                Button("Create opencode.json") { workspace.createConfigIfNeeded() }
                                    .buttonStyle(.borderedProminent)
                            }
                            Spacer()
                            Text("Version 1.0.0").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private func binaryRow(_ name: String, path: String?, version: String?) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(path == nil ? Color.orange : Color.green)
                .frame(width: 7, height: 7)
            Text(name).font(.callout.monospaced()).frame(width: 80, alignment: .leading)
            Text(path ?? "not found").font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            if let version, !version.isEmpty {
                Text(version).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
        }
    }
}
