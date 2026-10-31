import SwiftUI

struct ToolEditorTarget: Identifiable {
    let id = UUID()
    var fileName: String
    var contents: String
    var existing: ToolFile?
}

@MainActor
struct ToolsView: View {
    @EnvironmentObject private var workspace: Workspace
    @State private var target: ToolEditorTarget?
    @State private var scope: Skill.Scope = .global

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                introCard
                listCard
            }
            .padding(20)
        }
        .sheet(item: $target) { item in
            ToolEditorSheet(target: item, scope: scope)
                .environmentObject(workspace)
        }
    }

    private var introCard: some View {
        SectionCard(title: "Custom tools",
                    subtitle: "Files in tools/ export a tool() that opencode can call like a built-in.") {
            HStack(spacing: 10) {
                Menu {
                    ForEach(ToolManager.templates) { template in
                        Button(template.name) {
                            target = ToolEditorTarget(fileName: template.fileName, contents: template.body, existing: nil)
                        }
                    }
                } label: {
                    Label("New tool from template", systemImage: "plus.square.on.square")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 220)

                Button {
                    target = ToolEditorTarget(fileName: "my-tool.ts", contents: "", existing: nil)
                } label: {
                    Label("Blank tool", systemImage: "doc.badge.plus")
                }

                Spacer()

                Picker("Scope", selection: $scope) {
                    Text("Global").tag(Skill.Scope.global)
                    Text("Project").tag(Skill.Scope.project)
                }
                .pickerStyle(.segmented)
                .frame(width: 190)
                .disabled(workspace.projectRoot == nil)

                Button {
                    workspace.openFolder(scope == .project && workspace.projectRoot != nil
                                         ? Paths.projectToolsDir(workspace.projectRoot!)
                                         : Paths.globalToolsDir)
                } label: {
                    Label("Open folder", systemImage: "folder")
                }
            }
        }
    }

    private var listCard: some View {
        SectionCard(title: "Installed tools", subtitle: "\(workspace.allTools.count) files") {
            if workspace.allTools.isEmpty {
                EmptyStateView(symbol: "wrench.and.screwdriver", title: "No custom tools",
                               message: "Start from a template — each one is a complete, working tool definition.")
            } else {
                VStack(spacing: 0) {
                    ForEach(workspace.allTools) { tool in
                        HStack(spacing: 10) {
                            Image(systemName: "wrench.and.screwdriver")
                                .foregroundStyle(.orange)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tool.fileName).font(.callout.weight(.medium))
                                Text("\(FS.prettySize(tool.size))" + (tool.modified.map { " · " + $0.formatted(date: .abbreviated, time: .shortened) } ?? ""))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Edit") {
                                target = ToolEditorTarget(
                                    fileName: tool.fileName,
                                    contents: ToolManager.read(tool),
                                    existing: tool
                                )
                            }
                            .buttonStyle(.link)
                            Button("Reveal") { workspace.reveal(tool.url) }
                                .buttonStyle(.link)
                            Button(role: .destructive) {
                                workspace.deleteTool(tool)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 8)
                        if tool.id != workspace.allTools.last?.id { Divider() }
                    }
                }
            }
        }
    }
}

@MainActor
struct ToolEditorSheet: View {
    let target: ToolEditorTarget
    let scope: Skill.Scope

    @EnvironmentObject private var workspace: Workspace
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(target.existing == nil ? "New tool" : "Edit \(target.fileName)")
                    .font(.title3.weight(.semibold))
                Spacer()
                Pill(text: scope.rawValue, tint: .orange)
            }

            HStack(spacing: 8) {
                Text("File name").font(.callout).foregroundStyle(.secondary)
                TextField("my-tool.ts", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                Spacer()
            }

            TextEditor(text: $text)
                .font(.system(size: 11.5, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.1)))
                .frame(minHeight: 380)

            HStack {
                Text("Saved to \(scope == .global ? Paths.tilde(Paths.globalToolsDir) : "the project's .opencode/tools")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    workspace.saveTool(name: name, contents: text, scope: scope)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 780, height: 600)
        .onAppear {
            name = target.fileName
            text = target.contents
        }
    }
}
