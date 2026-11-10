#if os(macOS)
    import Foundation

    struct StoreEngineRequest: Encodable, Sendable {
        var operation: String
        var state: Data?
        var email: String?
        var password: String?
        var code: String?
        var appID: Int64?
        var bundleID: String?
        var platform: String?
        var versionID: String?
        var output: String?
    }

    struct StoreEngineResponse: Decodable, Sendable {
        struct Account: Decodable, Sendable {
            var email: String
            var name: String
            var store: String
            var dsid: String
        }

        var kind: String
        var state: Data?
        var account: Account?
        var error: String?
        var code: String?
        var versions: [String]?
        var version: String?
        var releaseDate: String?
        var fraction: Double?
    }

    struct StoreEngineError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    enum StoreEngineProcess {
        static func run(_ request: StoreEngineRequest, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> StoreEngineResponse {
            let input = try JSONEncoder().encode(request)
            let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/AssppStore")
            guard FileManager.default.isExecutableFile(atPath: helper.path) else {
                throw StoreEngineError(message: String(localized: "The App Store engine is missing. Reinstall the complete Asspp app."))
            }
            let lifetime = ProcessLifetime()
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    DispatchQueue.global(qos: .userInitiated).async {
                        do {
                            let result = try execute(helper: helper, input: input, lifetime: lifetime, progress: progress)
                            continuation.resume(returning: result)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            } onCancel: {
                lifetime.cancel()
            }
        }

        private static func execute(helper: URL, input: Data, lifetime: ProcessLifetime, progress: @escaping @Sendable (Double) -> Void) throws -> StoreEngineResponse {
            let process = Process()
            let stdin = Pipe()
            let stdout = Pipe()
            process.executableURL = helper
            process.arguments = []
            process.standardInput = stdin
            process.standardOutput = stdout
            // Upstream diagnostics may contain server responses. Never forward them to the app log.
            process.standardError = FileHandle.nullDevice
            try lifetime.start(process)
            defer { lifetime.cancel() }
            try stdin.fileHandleForWriting.write(contentsOf: input)
            try stdin.fileHandleForWriting.close()
            var buffer = Data()
            var result: StoreEngineResponse?
            while let chunk = try stdout.fileHandleForReading.read(upToCount: 65536), !chunk.isEmpty {
                buffer.append(chunk)
                guard buffer.count <= 8 * 1024 * 1024 else {
                    throw StoreEngineError(message: "The App Store engine returned an oversized response.")
                }
                while let newline = buffer.firstIndex(of: 10) {
                    let line = Data(buffer[..<newline])
                    buffer.removeSubrange(...newline)
                    let event = try JSONDecoder().decode(StoreEngineResponse.self, from: line)
                    if event.kind == "progress", let fraction = event.fraction {
                        progress(min(0.99, max(0, fraction)))
                    } else if event.kind == "result" {
                        result = event
                    }
                }
            }
            process.waitUntilExit()
            if process.terminationStatus == 0, let result, buffer.isEmpty { return result }
            try lifetime.checkCancellation()
            throw StoreEngineError(message: String(localized: "The App Store engine stopped unexpectedly. Please try again."))
        }
    }

    /// Cancellation can arrive before the background thread starts the child.
    private final class ProcessLifetime: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?
        private var cancelled = false

        func start(_ process: Process) throws {
            lock.lock()
            defer { lock.unlock() }
            guard !cancelled else { throw CancellationError() }
            self.process = process
            try process.run()
        }

        func checkCancellation() throws {
            lock.lock()
            defer { lock.unlock() }
            if cancelled { throw CancellationError() }
        }

        func cancel() {
            lock.lock()
            cancelled = true
            let process = process
            lock.unlock()
            guard let process, process.isRunning else { return }
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
    }
#endif
