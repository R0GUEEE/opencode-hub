import SwiftUI

struct DependenciesView: View {
    @EnvironmentObject private var workspace: Workspace
    @State private var scope: DependencyScope = .global
    @State private var name = ""
    @State private var requirement = ""
    @State private var section: DependencySection = .dependencies
    @State private var lookup: NpmPackage?
    @State private var lookingUp = false
    @State private var editTarget: PackageDependency?
    @State private var editRequirement = ""

    private var store: DependencyStore { workspace.dependencies }

    private var missing: [String] {
        DependencyInstaller.missing(base: store.base, document: store.document)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                scopeBar
                if let error = store.loadError {
                    errorCard(error)
                }
                summaryCard
                addCard
                listCard
            }
            .padding(20)
        }
        .sheet(item: $editTarget) { dependency in
            editSheet(dependency)
        }
        .onAppear {
            workspace.loadDependencies(scope)
        }
    }

    private var scopeBar: some View {
        HStack(spacing: 12) {
            Picker("Scope", selection: $scope) {
                ForEach(DependencyScope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)
            .onChange(of: scope) { newValue in
                workspace.loadDependencies(newValue)
            }

            Text(Paths.tilde(store.fileURL))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            if scope == .project && workspace.projectRoot == nil {
                Button("Choose project…") { workspace.chooseProject() }
            }
            Text(DependencyInstaller.packageManager().map { "via \($0)" } ?? "bun/npm not found")
                .font(.caption)
                .foregroundStyle(DependencyInstaller.packageManager() == nil ? Color.orange : Color.secondary)
        }
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.callout)
            Spacer()
            Button("Reload") { store.reload() }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.1)))
    }

    private var summaryCard: some View {
        SectionCard(title: "package.json",
                    subtitle: "The manifest opencode installs for local plugins and custom tools") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    statusPill("file", store.exists ? "present" : "missing", good: store.exists)
                    statusPill("packages", "\(store.packages.count)", good: !store.packages.isEmpty)
                    statusPill("installed", "\(store.installedCount)",
                               good: store.packages.isEmpty || store.nodeModulesPresent)
                    if let lock = store.lockfileName {
                        statusPill("lockfile", lock, good: true)
                    }
                    Spacer()
                    if let modified = store.modifiedAt {
                        Text(modified.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                if !missing.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                        Text("\(missing.count) declared package\(missing.count == 1 ? "" : "s") not installed: \(missing.prefix(4).joined(separator: ", "))\(missing.count > 4 ? "…" : "")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Divider()

                HStack(spacing: 10) {
                    Button {
                        Task { await workspace.installDependencies() }
                    } label: {
                        Label("Install now", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!store.exists || store.packages.isEmpty || workspace.busy != nil)

                    Button {
                        Task { await workspace.pinDependenciesToLatest() }
                    } label: {
                        Label("Pin latest to versions", systemImage: "pin")
                    }
                    .disabled(store.packages.isEmpty || workspace.busy != nil)

                    Spacer()

                    Button {
                        workspace.revealPackageJSON()
                    } label: {
                        Label("Reveal", systemImage: "folder")
                    }
                    Button {
                        workspace.openDependencyFolder()
                    } label: {
                        Label("Open folder", systemImage: "arrow.up.forward.app")
                    }
                }

                Text("opencode runs `bun install` in this folder on every start. Installing here just makes the first run after an edit fast — and surfaces resolution errors now instead of in the TUI.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var addCard: some View {
        SectionCard(title: "Add a package", subtitle: "Anything a plugin or tool imports must be declared here") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    TextField("package name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 180)
                        .onSubmit { add() }
                    TextField("latest", text: $requirement)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                    Picker("Section", selection: $section) {
                        ForEach(DependencySection.allCases) { section in
                            Text(section.title).tag(section)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 130)

                    Button("Add") { add() }
                        .buttonStyle(.borderedProminent)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || workspace.busy != nil)

                    Button {
                        Task { await resolve() }
                    } label: {
                        if lookingUp { ProgressView().controlSize(.small) }
                        else { Text("Look up") }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || lookingUp)
                }

                if let lookup {
                    HStack(spacing: 8) {
                        Pill(text: "v\(lookup.version)", tint: .blue)
                        Text(lookup.summary.isEmpty ? lookup.name : lookup.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Button("Use ^\(lookup.version)") {
                            requirement = "^" + lookup.version
                        }
                        .font(.caption)
                    }
                } else {
                    Text("Range syntax: latest, 1.2.3, ^1.2.3, ~1.2, >=1.2 <2, or file:../local-pkg")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var listCard: some View {
        SectionCard(title: "Declared packages", subtitle: store.summary) {
            if store.packages.isEmpty {
                EmptyStateView(symbol: "shippingbox", title: "Nothing declared",
                               message: "Add a package above. Plugin code that does `import { z } from \"zod\"` needs zod here.")
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(DependencySection.allCases) { group in
                        let rows = store.packages.filter { $0.section == group }
                        if !rows.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: group.symbol).font(.caption2)
                                Text(group.title.uppercased())
                                    .font(.system(size: 10, weight: .semibold))
                                    .tracking(0.6)
                            }
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .padding(.bottom, 4)

                            ForEach(rows) { dependency in
                                row(dependency)
                                if dependency.id != rows.last?.id { Divider() }
                            }
                        }
                    }
                }
            }
        }
    }

    private func row(_ dependency: PackageDependency) -> some View {
        HStack(spacing: 10) {
            Image(systemName: missing.contains(dependency.name) ? "circle.dashed" : "shippingbox")
                .foregroundStyle(missing.contains(dependency.name) ? Color.orange : Color.accentColor)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(dependency.name).font(.callout.weight(.medium))
                Text(dependency.isLocal ? "local package" : "npm registry")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Text(dependency.displayRequirement)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            Menu {
                Button("Edit range…") {
                    editRequirement = dependency.requirement
                    editTarget = dependency
                }
                Button("Set to latest") {
                    Task { await workspace.setDependencyRequirement(dependency, requirement: "latest") }
                }
                Button("Resolve exact version") {
                    Task { await resolveInto(dependency) }
                }
                Divider()
                Button("Copy name") { workspace.copyToPasteboard(dependency.name) }
                Button("Remove", role: .destructive) {
                    Task { await workspace.removeDependency(dependency) }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 26)
        }
        .padding(.vertical, 7)
    }

    private func editSheet(_ dependency: PackageDependency) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Version range for \(dependency.name)").font(.headline)
            TextField("^1.2.3", text: $editRequirement)
                .textFieldStyle(.roundedBorder)
            Text("Anything npm accepts: latest, 1.2.3, ^1.2.3, ~1.2, >=1.2 <2.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { editTarget = nil }
                Button("Save") {
                    let requirement = editRequirement
                    editTarget = nil
                    Task { await workspace.setDependencyRequirement(dependency, requirement: requirement) }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    private func statusPill(_ title: String, _ value: String, good: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(good ? Color.primary : Color.orange)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.04)))
    }

    private func add() {
        let package = name.trimmingCharacters(in: .whitespaces)
        guard !package.isEmpty else { return }
        let range = requirement.trimmingCharacters(in: .whitespaces)
        name = ""
        requirement = ""
        lookup = nil
        Task { await workspace.addDependency(name: package, requirement: range, section: section) }
    }

    private func resolve() async {
        lookingUp = true
        defer { lookingUp = false }
        let package = NpmPlugin.parse(name.trimmingCharacters(in: .whitespaces)).name
        lookup = try? await NPMRegistry.info(package)
        if lookup == nil {
            workspace.errorMessage = "npm has no package named \(package)."
        }
    }

    private func resolveInto(_ dependency: PackageDependency) async {
        guard let info = try? await NPMRegistry.info(dependency.name) else {
            workspace.errorMessage = "Could not resolve \(dependency.name) on npm."
            return
        }
        await workspace.setDependencyRequirement(dependency, requirement: "^" + info.version)
    }
}
