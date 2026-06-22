import Foundation

public enum RemoteTransportMessageType: String, Codable, Equatable, Sendable {
    case command
    case result
    case error
}

public struct RemoteTransportMessage: Codable, Equatable, Sendable {
    public var id: UUID
    public var type: RemoteTransportMessageType
    public var command: RemoteCommand?
    public var result: RemoteCommandResult?
    public var errorMessage: String?

    public init(
        id: UUID = UUID(),
        type: RemoteTransportMessageType,
        command: RemoteCommand? = nil,
        result: RemoteCommandResult? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.type = type
        self.command = command
        self.result = result
        self.errorMessage = errorMessage
    }
}

public struct EncryptedRemoteTransportCodec: Sendable {
    private let cipher: any TransportCipher

    public init(cipher: any TransportCipher = AESGCMTransportCipher()) {
        self.cipher = cipher
    }

    public func encode(_ message: RemoteTransportMessage, key: SymmetricTransportKey) throws -> EncryptedTransportEnvelope {
        let data = try JSONEncoder().encode(message)
        return try cipher.seal(data, using: key)
    }

    public func decode(_ envelope: EncryptedTransportEnvelope, key: SymmetricTransportKey) throws -> RemoteTransportMessage {
        let data = try cipher.open(envelope, using: key)
        return try JSONDecoder().decode(RemoteTransportMessage.self, from: data)
    }
}

