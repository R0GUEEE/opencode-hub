import SwiftUI

@MainActor
struct MCPView: View {
    @EnvironmentObject private var workspace: Workspace
    @State private var showAdd = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard
                listCard
            }
            .padding(20)
        }
        .sheet(isPresented: $showAdd) {
            AddMCPSheet().environmentObject(workspace)
        }
    }

    private var headerCard: some View {
        SectionCard(title: "MCP servers",
                    subtitle: "Written to the mcp object in opencode.json. opencode starts local servers itself.") {
            HStack(spacing: 10) {
                Menu {
                    ForEach(MCPPreset.all) { preset in
                        Button(preset.name) {
                            workspace.performMCPPreset(preset)
                        }
                    }
                } label: {
                    Label("Add a preset", systemImage: "square.stack.3d.up")
                }
                .frame(width: 170)

                Button {
                    showAdd = true
                } label: {
                    Label("Add custom server", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)

                Spacer()

                Button {
                    workspace.openConfig()
                } label: {
                    Label("Open config", systemImage: "doc.text")
                }
            }
        }
    }

    private var listCard: some View {
        SectionCard(title: "Configured", subtitle: "\(workspace.servers.count) servers") {
            if workspace.servers.isEmpty {
                EmptyStateView(symbol: "antenna.radiowaves.left.and.right", title: "No MCP servers",
                               message: "Add a preset such as Filesystem or Playwright, or point at your own endpoint.")
            } else {
                VStack(spacing: 0) {
                    ForEach(workspace.servers) { server in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: server.isRemote ? "cloud" : "terminal")
                                .foregroundStyle(.green)
                                .frame(width: 18)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(server.key).font(.callout.weight(.medium))
                                    Pill(text: server.type, tint: server.isRemote ? .teal : .green)
                                    if !server.enabled { Pill(text: "disabled", tint: .secondary) }
                                }
                                Text(server.summary)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                if !server.environment.isEmpty {
                                    Text(server.environment.keys.sorted().joined(separator: ", ") + " set")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { server.enabled },
                                set: { workspace.setMCPEnabled(server, enabled: $0) }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)

                            Button(role: .destructive) {
                                workspace.removeMCP(server)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 9)
                        if server.id != workspace.servers.last?.id { Divider() }
                    }
                }
            }
        }
    }
}

@MainActor
struct AddMCPSheet: View {
    @EnvironmentObject private var workspace: Workspace
    @Environment(\.dismiss) private var dismiss

    @State private var key = ""
    @State private var type = "local"
    @State private var command = "npx -y @modelcontextprotocol/server-filesystem ~/Projects"
    @State private var url = ""
    @State private var environment = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add MCP server").font(.title3.weight(.semibold))

            Form {
                TextField("Key", text: $key, prompt: Text("filesystem"))
                Picker("Type", selection: $type) {
                    Text("Local (stdio)").tag("local")
                    Text("Remote (HTTP)").tag("remote")
                }
                .pickerStyle(.segmented)

                if type == "local" {
                    TextField("Command", text: $command, prompt: Text("npx -y @modelcontextprotocol/server-filesystem ~/Projects"))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Environment").font(.caption).foregroundStyle(.secondary)
                        TextEditor(text: $environment)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(height: 80)
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.12)))
                        Text("One KEY=value per line.").font(.caption2).foregroundStyle(.tertiary)
                    }
                } else {
                    TextField("URL", text: $url, prompt: Text("https://mcp.example.com/mcp"))
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") {
                    workspace.addMCP(key: key, type: type, command: command, url: url, environment: environment)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520, height: 440)
    }
}
