import Foundation

public enum SandboxExecutionRisk: String, Codable, Equatable, Sendable {
    case low
    case high
}

public struct SandboxCommand: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var instruction: String
    public var risk: SandboxExecutionRisk
    public var timeoutSeconds: TimeInterval

    public init(
        id: UUID = UUID(),
        instruction: String,
        risk: SandboxExecutionRisk,
        timeoutSeconds: TimeInterval = 30
    ) {
        self.id = id
        self.instruction = instruction
        self.risk = risk
        self.timeoutSeconds = timeoutSeconds
    }
}

public struct SandboxExecutionResult: Codable, Equatable, Sendable {
    public var commandId: UUID
    public var output: String
    public var completedAt: Date

    public init(commandId: UUID, output: String, completedAt: Date = Date()) {
        self.commandId = commandId
        self.output = output
        self.completedAt = completedAt
    }
}

public enum SandboxExecutionError: Error, Equatable {
    case commandTimedOut
    case unsupportedInstruction
}

public protocol SandboxExecutor: Sendable {
    func execute(_ command: SandboxCommand) async throws -> SandboxExecutionResult
}

public struct MockSandboxExecutor: SandboxExecutor {
    public init() {}

    public func execute(_ command: SandboxCommand) async throws -> SandboxExecutionResult {
        SandboxExecutionResult(
            commandId: command.id,
            output: "Sandbox mock executed: \(command.instruction)"
        )
    }
}

