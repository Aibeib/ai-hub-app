import Foundation
import AIAgentHubCore

struct AuthorizationRequest: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let continuation: CheckedContinuation<Bool, Never>
}

@MainActor
protocol AppAuthorizationPresenter: AnyObject {
    var pendingAuthorization: AuthorizationRequest? { get set }
}

@MainActor
final class AppAuthorizationBroker: ToolAuthorization, RemoteCommandAuthorization, @unchecked Sendable {
    weak var presenter: (any AppAuthorizationPresenter)?

    func authorize(
        tool: ToolDefinition,
        riskLevel: ToolRiskLevel,
        arguments: [String: ToolArgument]
    ) async -> ToolAuthorizationDecision {
        guard riskLevel == .high else {
            return .approved
        }

        let approved = await requestAuthorization(
            title: "Approve high-risk tool?",
            message: "\(tool.name) wants to run. Review before allowing this action."
        )
        return approved ? .approved : .cancelled
    }

    func authorize(command: RemoteCommand, device: BoundDevice) async -> RemoteCommandAuthorizationDecision {
        guard command.risk == .high else {
            return .approved
        }

        let approved = await requestAuthorization(
            title: "Approve remote command?",
            message: "\(device.name) will receive: \(command.instruction)"
        )
        return approved ? .approved : .cancelled
    }

    private func requestAuthorization(title: String, message: String) async -> Bool {
        await withCheckedContinuation { continuation in
            presenter?.pendingAuthorization = AuthorizationRequest(
                title: title,
                message: message,
                continuation: continuation
            )
        }
    }
}

