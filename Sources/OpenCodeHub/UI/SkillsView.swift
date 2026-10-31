import SwiftUI

@MainActor
struct SkillsView: View {
    @EnvironmentObject private var workspace: Workspace
    @State private var source = ""
    @State private var scope: Skill.Scope = .global
    @State private var detail: Skill?
    @State private var filter = ""

    private var visible: [Skill] {
        let all = workspace.allSkills
        guard !filter.trimmingCharacters(in: .whitespaces).isEmpty else { return all }
        return all.filter {
            $0.displayName.localizedCaseInsensitiveContains(filter)
                || $0.summary.localizedCaseInsensitiveContains(filter)
                || $0.slug.localizedCaseInsensitiveContains(filter)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                installCard
                listCard
            }
            .padding(20)
        }
        .searchable(text: $filter, prompt: "Filter installed skills")
        .sheet(item: $detail) { skill in
            SkillDetailSheet(skill: skill)
                .environmentObject(workspace)
        }
    }

    private var installCard: some View {
        SectionCard(title: "Install a skill",
                    subtitle: "A skill is a folder with SKILL.md. Point at a GitHub repo, a subfolder, or a raw SKILL.md URL.") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    TextField("anthropics/skills/document-skills/pdf", text: $source)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { install() }
                    Picker("Scope", selection: $scope) {
                        Text("Global").tag(Skill.Scope.global)
                        Text("Project").tag(Skill.Scope.project)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                    .disabled(workspace.projectRoot == nil && scope == .project)
                    Button("Install") { install() }
                        .buttonStyle(.borderedProminent)
                        .disabled(source.trimmingCharacters(in: .whitespaces).isEmpty || workspace.busy != nil)
                }
                HStack(spacing: 10) {
                    Button {
                        Task { await workspace.installSkillFromFolder(scope: scope) }
                    } label: {
                        Label("Install from folder…", systemImage: "folder.badge.plus")
                    }
                    Button {
                        workspace.openFolder(Paths.globalSkillsDir)
                    } label: {
                        Label("Open skills folder", systemImage: "folder")
                    }
                    Spacer()
                    Text(scope == .global
                         ? "Target: \(Paths.tilde(Paths.globalSkillsDir))"
                         : "Target: \(workspace.projectRoot.map { Paths.tilde(Paths.projectSkillsDir($0)) } ?? "pick a project")")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var listCard: some View {
        SectionCard(title: "Installed skills", subtitle: "\(workspace.allSkills.count) found") {
            if visible.isEmpty {
                EmptyStateView(symbol: "book.closed", title: "No skills yet",
                               message: "Install one above, or browse the catalog for curated Agent Skills.")
            } else {
                VStack(spacing: 0) {
                    ForEach(visible) { skill in
                        Button {
                            detail = skill
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "book.closed")
                                    .foregroundStyle(.blue)
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(skill.displayName).font(.callout.weight(.medium))
                                        Pill(text: skill.scope.rawValue, tint: skill.scope == .global ? .blue : .teal)
                                        if let license = skill.license, !license.isEmpty {
                                            Pill(text: license, tint: .secondary)
                                        }
                                    }
                                    Text(skill.summary.isEmpty ? "No description in SKILL.md" : skill.summary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("\(skill.fileCount) files").font(.caption2).foregroundStyle(.tertiary)
                                    if let modified = skill.modified {
                                        Text(modified.formatted(date: .abbreviated, time: .omitted))
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                Button(role: .destructive) {
                                    workspace.uninstall(skill)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .help("Move \(skill.slug) to the Trash")
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 9)
                        }
                        .buttonStyle(.plain)
                        if skill.id != visible.last?.id { Divider() }
                    }
                }
            }
        }
    }

    private func install() {
        let value = source.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }
        source = ""
        Task { await workspace.installSkill(source: value, scope: scope) }
    }
}

@MainActor
struct SkillDetailSheet: View {
    let skill: Skill
    @EnvironmentObject private var workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(skill.displayName).font(.title3.weight(.semibold))
                    Text(Paths.tilde(skill.path)).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Spacer()
                Pill(text: skill.scope.rawValue, tint: .blue)
            }

            Text(skill.summary.isEmpty ? "No description." : skill.summary)
                .font(.callout)
                .foregroundStyle(.secondary)

            Divider()

            ScrollView {
                Text(text.isEmpty ? "SKILL.md is missing." : text)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 300)

            HStack {
                Button {
                    workspace.reveal(skill.path)
                } label: {
                    Label("Reveal", systemImage: "folder")
                }
                Button {
                    workspace.copyToPasteboard(text)
                } label: {
                    Label("Copy SKILL.md", systemImage: "doc.on.doc")
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 660, height: 560)
        .onAppear { text = skill.body ?? "" }
    }
}
