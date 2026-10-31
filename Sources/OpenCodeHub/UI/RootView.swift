import SwiftUI

enum HubSection: String, CaseIterable, Identifiable, Hashable {
    case dashboard, catalog, dependencies, plugins, skills, tools, mcp, logs, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Overview"
        case .catalog: return "Catalog"
        case .dependencies: return "Dependencies"
        case .plugins: return "Plugins"
        case .skills: return "Skills"
        case .tools: return "Tools"
        case .mcp: return "MCP servers"
        case .logs: return "Activity"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .catalog: return "shippingbox"
        case .dependencies: return "shippingbox.and.arrow.backward"
        case .plugins: return "puzzlepiece.extension"
        case .skills: return "book.closed"
        case .tools: return "wrench.and.screwdriver"
        case .mcp: return "antenna.radiowaves.left.and.right"
        case .logs: return "list.bullet.rectangle"
        case .settings: return "gearshape"
        }
    }

    static let groups: [(String, [HubSection])] = [
        ("Overview", [.dashboard, .catalog]),
        ("Install", [.dependencies, .plugins, .skills, .tools, .mcp]),
        ("System", [.logs, .settings]),
    ]
}

@MainActor
struct RootView: View {
    @EnvironmentObject private var workspace: Workspace
    @State private var selection: HubSection? = .dashboard

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
                .navigationTitle(current.title)
                .toolbar { toolbar }
        }
        .task { await workspace.bootstrap() }
        .overlay(alignment: .bottom) { banners }
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("OK", role: .cancel) { workspace.errorMessage = nil }
        } message: {
            Text(workspace.errorMessage ?? "")
        }
        .task(id: workspace.notice) {
            guard workspace.notice != nil else { return }
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            workspace.notice = nil
        }
    }

    private var current: HubSection { selection ?? .dashboard }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { workspace.errorMessage != nil },
            set: { if !$0 { workspace.errorMessage = nil } }
        )
    }

    private var sidebar: some View {
        List(selection: $selection) {
            ForEach(HubSection.groups, id: \.0) { group in
                Section(group.0) {
                    ForEach(group.1) { section in
                        Label(section.title, systemImage: section.symbol)
                            .tag(section)
                            .badge(badge(for: section))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 208, ideal: 222, max: 260)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Divider()
                HStack(spacing: 6) {
                    Circle()
                        .fill(workspace.cli.opencodeAvailable ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                    Text(workspace.cli.opencodeVersion.map { "opencode \($0)" } ?? "opencode not found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
            .background(.bar)
        }
    }

    private func badge(for section: HubSection) -> Int {
        switch section {
        case .dependencies: return workspace.dependencies.packages.count
        case .plugins: return workspace.npmPlugins.count + workspace.allLocalPlugins.count
        case .skills: return workspace.allSkills.count
        case .tools: return workspace.allTools.count
        case .mcp: return workspace.servers.count
        default: return 0
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch current {
        case .dashboard: DashboardView(selection: $selection)
        case .catalog: CatalogView()
        case .dependencies: DependenciesView()
        case .plugins: PluginsView()
        case .skills: SkillsView()
        case .tools: ToolsView()
        case .mcp: MCPView()
        case .logs: LogsView()
        case .settings: SettingsView()
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if let busy = workspace.busy {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(busy).font(.caption).foregroundStyle(.secondary)
                }
            }
            Button {
                workspace.chooseProject()
            } label: {
                Label(workspace.projectRoot.map { Paths.tilde($0) } ?? "No project", systemImage: "folder.badge.gearshape")
            }
            .help("Set the project folder used for .opencode/ entries")

            Button {
                workspace.refresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r")
            .help("Reload opencode.json and rescan folders")
        }
    }

    private var banners: some View {
        VStack(spacing: 10) {
            if let notice = workspace.notice {
                NoticeBanner(text: notice) { workspace.notice = nil }
            }
            if let busy = workspace.busy {
                BusyBanner(label: busy)
            }
        }
        .padding(.bottom, 18)
        .animation(.easeInOut(duration: 0.18), value: workspace.notice)
    }
}
