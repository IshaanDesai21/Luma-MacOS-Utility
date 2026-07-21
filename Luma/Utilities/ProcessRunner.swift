import Foundation

enum ProcessRunnerError: LocalizedError {
    case launchFailed(String)
    case nonZeroExit(Int32)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let reason): return reason
        case .nonZeroExit(let code): return "Process exited with code \(code)."
        }
    }
}

/// Runs a command-line tool asynchronously without blocking a thread.
enum ProcessRunner {
    static func run(_ launchPath: String, arguments: [String], allowFailure: Bool = false) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        do {
            try process.run()
        } catch {
            throw ProcessRunnerError.launchFailed(error.localizedDescription)
        }

        let status: Int32 = await withCheckedContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
        }

        if status != 0 && !allowFailure {
            throw ProcessRunnerError.nonZeroExit(status)
        }
    }
}
