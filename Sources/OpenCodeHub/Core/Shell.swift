import Foundation

struct ShellResult: Sendable {
    let command: String
    let status: Int32
    let stdout: String
    let stderr: String
    let duration: TimeInterval

    var output: String {
        let out = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let err = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if out.isEmpty { return err }
        if err.isEmpty { return out }
        return out + "\n" + err
    }

    var succeeded: Bool { status == 0 }
}

enum ShellError: LocalizedError {
    case notFound(String)
    case launch(String)
    case failed(ShellResult)
    case timeout(String, TimeInterval)

    var errorDescription: String? {
        switch self {
        case .notFound(let command):
            return "\(command) was not found on PATH. Install it, or set the binary path in Settings."
        case .launch(let message):
            return message
        case .failed(let result):
            let detail = result.output
            let tail = detail.count > 1400 ? String(detail.suffix(1400)) : detail
            return "\(result.command) exited with status \(result.status).\n\n\(tail)"
        case .timeout(let command, let seconds):
            return "\(command) did not finish within \(Int(seconds))s and was terminated."
        }
    }
}

/// Minimal thread-safe box for values shared with dispatch closures.
final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T

    init(_ value: T) { self.value = value }

    var current: T {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func set(_ newValue: T) {
        lock.lock(); value = newValue; lock.unlock()
    }

}

enum Shell {
    /// GUI apps do not inherit the login shell PATH, so build one explicitly.
    static var searchPath: [String] {
        var parts: [String] = []
        if let raw = ProcessInfo.processInfo.environment["PATH"] {
            parts.append(contentsOf: raw.split(separator: ":").map(String.init).filter { !$0.isEmpty })
        }
        let home = Paths.home.path
        let extras = [
            "/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", "/usr/local/sbin",
            home + "/.opencode/bin", home + "/.bun/bin", home + "/.local/bin",
            home + "/.npm-global/bin", home + "/.volta/bin", home + "/.cargo/bin",
            "/usr/bin", "/bin", "/usr/sbin", "/sbin"
        ]
        for dir in extras where !parts.contains(dir) { parts.append(dir) }
        return parts
    }

    static var pathString: String { searchPath.joined(separator: ":") }

    static func which(_ name: String) -> String? {
        let fm = FileManager.default
        if name.hasPrefix("/") {
            return fm.isExecutableFile(atPath: name) ? name : nil
        }
        for dir in searchPath {
            let candidate = dir + "/" + name
            if fm.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    static func run(
        _ executable: String,
        _ arguments: [String] = [],
        cwd: URL? = nil,
        env: [String: String] = [:],
        timeout: TimeInterval = 120
    ) async throws -> ShellResult {
        let label = ([executable] + arguments).joined(separator: " ")
        var resolved = executable
        if !executable.hasPrefix("/") {
            guard let found = which(executable) else { throw ShellError.notFound(executable) }
            resolved = found
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: resolved)
        process.arguments = arguments
        if let cwd { process.currentDirectoryURL = cwd }

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = pathString
        environment["NO_COLOR"] = "1"
        environment["GIT_TERMINAL_PROMPT"] = "0"
        for (key, value) in env { environment[key] = value }
        process.environment = environment

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        let once = Flag()
        let timedOut = Flag()
        let outData = Box<Data>(Data())
        let errData = Box<Data>(Data())
        let started = Date()

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ShellResult, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try process.run()
                } catch {
                    if once.claim() {
                        continuation.resume(throwing: ShellError.launch("Could not run \(label): \(error.localizedDescription)"))
                    }
                    return
                }

                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global(qos: .utility).async {
                    let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                    outData.set(data)
                    group.leave()
                }
                group.enter()
                DispatchQueue.global(qos: .utility).async {
                    let data = errPipe.fileHandleForReading.readDataToEndOfFile()
                    errData.set(data)
                    group.leave()
                }

                let killer = DispatchWorkItem {
                    if process.isRunning {
                        timedOut.set(true)
                        process.terminate()
                        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                        }
                    }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)

                process.waitUntilExit()
                killer.cancel()
                group.wait()

                let result = ShellResult(
                    command: label,
                    status: process.terminationStatus,
                    stdout: String(decoding: outData.current, as: UTF8.self),
                    stderr: String(decoding: errData.current, as: UTF8.self),
                    duration: Date().timeIntervalSince(started)
                )

                guard once.claim() else { return }
                if timedOut.current {
                    continuation.resume(throwing: ShellError.timeout(label, timeout))
                } else {
                    continuation.resume(returning: result)
                }
            }
        }
    }

    /// Runs a command and throws a readable error when it exits non-zero.
    @discardableResult
    static func check(
        _ executable: String,
        _ arguments: [String] = [],
        cwd: URL? = nil,
        env: [String: String] = [:],
        timeout: TimeInterval = 180
    ) async throws -> ShellResult {
        let result = try await run(executable, arguments, cwd: cwd, env: env, timeout: timeout)
        guard result.succeeded else { throw ShellError.failed(result) }
        return result
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    var firstLine: String {
        split(separator: "\n", maxSplits: 1).first.map(String.init) ?? self
    }
}

/// Single-use boolean latch used to guarantee exactly one continuation resume.
final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var current: Bool {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    @discardableResult
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if value { return false }
        value = true
        return true
    }

    func set(_ newValue: Bool) {
        lock.lock(); value = newValue; lock.unlock()
    }
}
