import Foundation

struct ToolTemplate: Identifiable, Hashable {
    let id: String
    let name: String
    let summary: String
    let fileName: String
    let body: String
}

enum ToolManager {
    static let allowedExtensions: Set<String> = ["ts", "js"]

    static func installed(in directory: URL) -> [ToolFile] {
        FS.children(directory, extensions: allowedExtensions).compactMap { url in
            guard !FS.isDirectory(url) else { return nil }
            return ToolFile(
                fileName: url.lastPathComponent,
                url: url,
                size: FS.size(url),
                modified: FS.modified(url)
            )
        }
        .sorted { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending }
    }

    static func read(_ tool: ToolFile) -> String {
        FS.read(tool.url) ?? ""
    }

    static func save(name: String, contents: String, in directory: URL) throws -> ToolFile {
        var fileName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if fileName.isEmpty { throw HubError.invalidInput("Give the tool a file name.") }
        if !allowedExtensions.contains((fileName as NSString).pathExtension.lowercased()) {
            fileName += ".ts"
        }
        try FS.ensure(directory)
        let destination = directory.appendingPathComponent(fileName)
        try FS.atomicWrite(contents, to: destination)
        return ToolFile(
            fileName: fileName,
            url: destination,
            size: FS.size(destination),
            modified: FS.modified(destination)
        )
    }

    static func delete(_ tool: ToolFile) throws {
        try FS.trash(tool.url)
    }

    static let templates: [ToolTemplate] = [
        ToolTemplate(
            id: "template-shell",
            name: "Run a command",
            summary: "Exposes one shell command as a tool with a validated argument.",
            fileName: "run-command.ts",
            body: """
            import { tool } from "@opencode-ai/plugin"

            export default tool({
              description: "Run a whitelisted command inside the current worktree and return its output.",
              args: {
                command: tool.schema.string().describe("Command to run, for example: npm test"),
              },
              async execute(args, context) {
                const allowed = /^(npm|pnpm|bun|git|make|cargo|go|python3?)\\b/
                if (!allowed.test(args.command)) {
                  throw new Error(`Refusing to run: ${args.command}`)
                }
                const result = await context.$`${args.command}`.cwd(context.worktree).nothrow()
                const stdout = result.stdout.toString().trim()
                const stderr = result.stderr.toString().trim()
                return [`exit: ${result.exitCode}`, stdout, stderr].filter(Boolean).join("\\n")
              },
            })
            """
        ),
        ToolTemplate(
            id: "template-http",
            name: "Fetch a URL",
            summary: "Fetches a URL and returns the body, truncated to a sane size.",
            fileName: "fetch-url.ts",
            body: """
            import { tool } from "@opencode-ai/plugin"

            export default tool({
              description: "Fetch a URL and return its body as text.",
              args: {
                url: tool.schema.string().url().describe("Absolute http(s) URL"),
                maxBytes: tool.schema.number().int().min(256).max(200_000).default(20_000),
              },
              async execute(args, context) {
                const response = await fetch(args.url, {
                  headers: { "user-agent": "opencode-custom-tool" },
                  signal: AbortSignal.timeout(15_000),
                })
                const text = await response.text()
                await context.client.app.log({
                  body: { service: "fetch-url", level: "info", message: `GET ${args.url}`, extra: { status: response.status } },
                })
                return `HTTP ${response.status}\\n\\n${text.slice(0, args.maxBytes)}`
              },
            })
            """
        ),
        ToolTemplate(
            id: "template-json",
            name: "Query a JSON file",
            summary: "Reads a JSON file from the worktree and returns a dotted path.",
            fileName: "json-query.ts",
            body: """
            import { tool } from "@opencode-ai/plugin"
            import { readFile } from "node:fs/promises"
            import { join } from "node:path"

            export default tool({
              description: "Read a JSON file from the worktree and return the value at a dotted path.",
              args: {
                file: tool.schema.string().describe("Path relative to the worktree, e.g. package.json"),
                path: tool.schema.string().default("").describe("Dotted path, e.g. scripts.build"),
              },
              async execute(args, context) {
                const target = join(context.worktree, args.file)
                if (!target.startsWith(context.worktree)) throw new Error("Path escapes the worktree")
                const document = JSON.parse(await readFile(target, "utf8"))
                const value = args.path
                  .split(".")
                  .filter(Boolean)
                  .reduce<any>((node, key) => (node == null ? node : node[key]), document)
                return JSON.stringify(value, null, 2) ?? "undefined"
              },
            })
            """
        ),
        ToolTemplate(
            id: "template-notify",
            name: "Notify when idle",
            summary: "Plugin (not a tool) that posts a macOS notification when a session goes idle.",
            fileName: "notify.ts",
            body: """
            import type { Plugin } from "@opencode-ai/plugin"

            export const NotifyOnIdle: Plugin = async ({ $ }) => ({
              event: async ({ event }) => {
                if (event.type !== "session.idle") return
                await $`osascript -e 'display notification "Session finished" with title "opencode"'`
              },
            })
            """
        ),
    ]
}
