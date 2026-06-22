import CryptoKit
import Foundation

public struct SymmetricTransportKey: Equatable, Sendable {
    public var rawValue: Data

    public init(rawValue: Data) {
        self.rawValue = rawValue
    }

    public static func random256Bit() -> SymmetricTransportKey {
        let key = SymmetricKey(size: .bits256)
        return SymmetricTransportKey(rawValue: key.withUnsafeBytes { Data($0) })
    }

    var symmetricKey: SymmetricKey {
        SymmetricKey(data: rawValue)
    }
}

public struct EncryptedTransportEnvelope: Codable, Equatable, Sendable {
    public var nonce: Data
    public var ciphertext: Data
    public var tag: Data

    public init(nonce: Data, ciphertext: Data, tag: Data) {
        self.nonce = nonce
        self.ciphertext = ciphertext
        self.tag = tag
    }
}

public enum TransportCipherError: Error, Equatable {
    case invalidNonce
    case authenticationFailed
}

public protocol TransportCipher: Sendable {
    func seal(_ plaintext: Data, using key: SymmetricTransportKey) throws -> EncryptedTransportEnvelope
    func open(_ envelope: EncryptedTransportEnvelope, using key: SymmetricTransportKey) throws -> Data
}

public struct AESGCMTransportCipher: TransportCipher {
    public init() {}

    public func seal(_ plaintext: Data, using key: SymmetricTransportKey) throws -> EncryptedTransportEnvelope {
        let sealed = try AES.GCM.seal(plaintext, using: key.symmetricKey)
        return EncryptedTransportEnvelope(
            nonce: Data(sealed.nonce),
            ciphertext: sealed.ciphertext,
            tag: sealed.tag
        )
    }

    public func open(_ envelope: EncryptedTransportEnvelope, using key: SymmetricTransportKey) throws -> Data {
        do {
            let nonce = try AES.GCM.Nonce(data: envelope.nonce)
            let sealedBox = try AES.GCM.SealedBox(
                nonce: nonce,
                ciphertext: envelope.ciphertext,
                tag: envelope.tag
            )
            return try AES.GCM.open(sealedBox, using: key.symmetricKey)
        } catch is CryptoKitError {
            throw TransportCipherError.authenticationFailed
        } catch TransportCipherError.invalidNonce {
            throw TransportCipherError.invalidNonce
        } catch {
            throw TransportCipherError.authenticationFailed
        }
    }
}

