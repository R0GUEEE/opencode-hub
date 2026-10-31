# OpenCode Hub

A native macOS app for installing **plugins**, **agent skills**, **custom tools**, and
**MCP servers** into [opencode](https://opencode.ai) — with a real backup, an atomic
write, and an undo path for every file it touches.

![platform](https://img.shields.io/badge/macOS-13%2B-blue) ![swift](https://img.shields.io/badge/Swift-5.9%2B-orange)

## What it manages

| Thing | Where it lands | How opencode loads it |
| --- | --- | --- |
| npm plugin | `plugin: [...]` in `~/.config/opencode/opencode.json` | installed with Bun at startup, cached in `~/.cache/opencode/node_modules` |
| local plugin | `~/.config/opencode/plugins/*.ts` or `.opencode/plugins/` | imported directly at startup |
| skill | `~/.config/opencode/skills/<name>/SKILL.md` | referenced through the `skill` tool |
| custom tool | `~/.config/opencode/tools/*.ts` | registered alongside built-in tools |
| MCP server | `mcp: {...}` in `opencode.json` | spawned / connected by the server |
| npm package | package.json in the config dir (or `<project>/.opencode`) | `bun install` at startup; imported by local plugins and custom tools |

Project-scoped writes go to `.opencode/plugins`, `.opencode/skills`, `.opencode/tools`
under the folder you pick in the toolbar. opencode uses **plural** directory names;
singular names still work as a legacy fallback, and the hub only ever writes plural.

## Why it is safe

* `opencode.json` is parsed as **JSONC** (comments and trailing commas are accepted),
  kept as an untyped dictionary, and written back with unknown keys intact.
* Every write is preceded by a timestamped copy in
  `~/Library/Application Support/OpenCodeHub/Backups` (last 40 kept) and lands through
  a sibling temp file plus `replaceItemAt`, so an interrupted save cannot truncate a
  config.
* Deletions go to the Trash, not `rm`.
* Skills are validated before install: a `SKILL.md` with frontmatter and a non-empty
  `description` is required, and the folder is copied only after that check passes.
* Remote catalogs and GitHub archives are fetched over HTTPS with a size-bounded
  reader; tarballs are unpacked into a temp folder and the result is a plain copy.

## Screens

* **Overview** — counts, environment health (opencode version, Bun, config validity),
  every path the app writes to, and a quick plugin installer with an npm lookup.
* **Dependencies** — the `package.json` opencode installs for local plugins and tools:
  add packages, resolve ranges against npm, install with Bun, and see which declarations
  have no `node_modules` entry.
* **Catalog** — curated Agent Skills, MCP presets, tool templates and plugin entries,
  filterable by kind, with live npm search for anything not curated.
* **Plugins** — npm entries with version pinning, local `.ts`/`.js` files, and a Bun
  prefetch button that warms the cache before the first `opencode` run.
* **Skills** — install from `owner/repo`, `owner/repo/subdir`, a `github.com/.../tree/...`
  URL, a raw `SKILL.md` URL, or a local folder. Preview any installed `SKILL.md`.
* **Tools** — a code editor with three working templates (run a command, fetch a URL,
  query a JSON file) plus a notification plugin example.
* **MCP servers** — presets for Filesystem, GitHub, Playwright, SQLite, Memory and
  Context7, a custom local/remote form, and enable/disable toggles.
* **Activity** — every command the hub ran, its exit status, and its output.
* **Settings** — install mode, project folder, remote catalog, binary discovery.

## Build

The app is a native Xcode target generated from `project.yml` by
[XcodeGen](https://github.com/yonaskolb/XcodeGen): asset catalog icon, entitlements,
Info.plist processing, universal architectures and signing all come from
`xcodebuild`, not from a shell script assembling a bundle by hand.

| Requirement | Version |
| --- | --- |
| macOS | 13.0+ |
| Xcode | 15+ (Swift 5.9) |
| XcodeGen | 2.38+ — `brew install xcodegen` |

```bash
brew install xcodegen
make project     # writes OpenCodeHub.xcodeproj from project.yml
make app         # -> build/Open Code Hub.app (universal, ad-hoc signed)
make dmg         # -> build/OpenCodeHub-1.1.0.dmg
open "build/Open Code Hub.app"
```

`make app` prefers `xcodegen` + `xcodebuild`. Without XcodeGen it falls back to
`swift build` plus a hand-assembled bundle: enough to run locally, but the asset
catalog is skipped.

Settings that matter, all in `project.yml`:

* `PRODUCT_NAME = "Open Code Hub"`, bundle id `dev.minis.opencodehub`
* `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`, overridable with `VERSION=`
* `CODE_SIGN_IDENTITY = "-"` (ad-hoc) and `ENABLE_HARDENED_RUNTIME = NO`, so an
  unnotarised build launches without a team certificate
* `Support/OpenCodeHub.entitlements`: sandbox **off** — the app edits an existing
  `~/.config/opencode` tree and runs the user's own binaries — with
  `network.client` and `files.user-selected.read-write` declared for the network
  calls and file panels it performs.

CI runs `swift build` as a fast compile gate, then builds the bundle with
`xcodebuild`, checks both architectures, `Assets.car`, the bundle identifier and
`codesign --verify --deep --strict`, and uploads `OpenCodeHub.zip`. A `v*` tag
publishes it as a release asset.

First launch after downloading: right-click → Open once, or

```bash
xattr -dr com.apple.quarantine "/Applications/Open Code Hub.app"
```

## Layout

```
project.yml                     XcodeGen spec: app target, assets, entitlements, scheme
Package.swift                   SwiftPM mirror of the same sources (compile gate)
Resources/Assets.xcassets       AppIcon: 10 sizes, compiled to Assets.car
Support/Info.plist              bundle metadata: category, version, icon name
Support/OpenCodeHub.entitlements  sandbox off, network client, user-selected files
Support/AppIcon.png             1024px master; scripts/make-iconset.py slices it
Sources/OpenCodeHub/
  OpenCodeHubApp.swift        App entry, menu commands, AppDelegate
  Core/Paths.swift            XDG-aware path resolution + project root discovery
  Core/Shell.swift            async Process runner (pipe-safe, timeout, explicit PATH)
  Core/FS.swift               atomic writes, backups, hashing, trash
  Core/JSONC.swift            comment/trailing-comma tolerant JSON round trip
  Core/AppLog.swift           activity feed + ~/Library/.../hub.log
  Models/Entities.swift       Plugin, Skill, Tool, MCPServer, CatalogEntry
  Services/ConfigStore.swift  opencode.json mutations
  Services/CLI.swift          binary discovery and `opencode plugin`
  Services/Registry.swift     npm registry + GitHub tarball/raw helpers
  Services/SkillManager.swift SKILL.md parsing, GitHub/folder/URL installs
  Services/PluginManager.swift npm + local plugin install, Bun prefetch
  Services/ToolManager.swift  tool templates and editor backing store
  Services/MCPManager.swift   presets, validation, env parsing
  Services/Catalog.swift      bundled catalog, remote overlay, npm search
  Services/Workspace.swift    observable orchestrator that the UI binds to
  Services/DependencyStore.swift      package.json model, validation, atomic edits
  Services/DependencyInstaller.swift  bun/npm plan, missing-package scan
  Services/WorkspaceExtras.swift      dependency actions, catalog reset
  UI/*.swift                  one file per screen
```

## Dependencies

Two different things share that word here.

**The app's own dependencies: none.** `Package.swift` declares no external Swift
packages — the app is SwiftUI + Foundation + AppKit + CryptoKit only. `make setup`
proves it: it checks the toolchain, parses the manifest with
`swift package dump-package`, resolves the (empty) graph, and builds. There is no
lockfile to drift and no supply chain inside the build.

**opencode's dependencies: managed by the app.** Local plugins and custom tools may
import npm packages. opencode resolves them from a `package.json` beside the config
(`~/.config/opencode/package.json`, or `<project>/.opencode/package.json`) and runs
`bun install` on startup. The Dependencies screen edits that file directly:

| Action | What happens |
| --- | --- |
| Add | validates the package name and range, writes `dependencies`/`devDependencies`, backs the file up first |
| Install now | runs `bun install` (falls back to `npm install`) in the config dir, streams the output to Activity |
| Pin latest to versions | resolves bare `latest`/`*` against the registry and writes `^x.y.z` |
| Missing scan | any declared package without a `node_modules/<name>` directory is flagged in the list and in the health panel |

Validation is deliberately strict: npm names must match
`^(@scope/)?[a-z0-9][a-z0-9._-]*$`, ranges are restricted to characters npm accepts,
and the file is written with sorted keys so diffs stay readable.

## Notes and honest limits

* npm plugin **installation** is done by opencode at startup with Bun. The hub writes
  the config entry and can prefetch, but it does not vendor packages into
  `node_modules` itself (other than running `bun add --no-save` in the cache).
* `opencode plugin <name>` is used only when you turn it on in Settings; the default
  path edits the config directly so the app works with no CLI installed.
* Skill installs from GitHub use `codeload.github.com` and `tar`; a private repo needs
  network credentials the hub does not handle.
* No telemetry, no network calls except the ones you trigger (npm lookups, catalog
  URLs, GitHub downloads).
