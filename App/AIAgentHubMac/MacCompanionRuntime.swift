import Foundation
import Observation
import AIAgentHubCore

@Observable
@MainActor
final class MacCompanionRuntime {
    var receivingEnabled = false
    var latestOutput = "Receiver disabled."
    private let executor: any SandboxExecutor

    init(executor: any SandboxExecutor = MockSandboxExecutor()) {
        self.executor = executor
    }

    func executeDemoCommand() async {
        guard receivingEnabled else {
            latestOutput = "Enable receiving before accepting remote commands."
            return
        }

        do {
            let result = try await executor.execute(
                SandboxCommand(
                    instruction: "Create a draft report in the app sandbox",
                    risk: .low
                )
            )
            latestOutput = result.output
        } catch {
            latestOutput = "Execution failed: \(error.localizedDescription)"
        }
    }
}

