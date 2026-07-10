import Foundation
#if canImport(Security)
import Security
#endif
#if canImport(CryptoKit)
import CryptoKit
#elseif canImport(InkWandCryptoC)
import InkWandCryptoC
#endif

public enum SecureChannelError: Error, Equatable {
    case unavailable
    case invalidKey
    case invalidEnvelope
    case authenticationFailed
}

public struct SecureHandshake: Sendable {
    public var publicKey: Data
    public var privateKey: Data
    public var nonce: Data

    public var publicKeyString: String { publicKey.base64EncodedString() }
    public var nonceString: String { nonce.base64EncodedString() }

    public init(publicKey: Data, privateKey: Data, nonce: Data) {
        self.publicKey = publicKey
        self.privateKey = privateKey
        self.nonce = nonce
    }
}

public final class SecureSession: @unchecked Sendable {
    private let key: Data

    public init(key: Data) {
        self.key = key
    }

    public func encrypt(_ message: InkMessage) throws -> EncryptedMessage {
        let plaintext = try JSONLineCodec.encodePayload(message)
        return try encryptData(plaintext)
    }

    public func encryptData(_ plaintext: Data) throws -> EncryptedMessage {
        let nonce = try SecureChannel.randomBytes(count: 12)
        let sealed = try SecureChannel.encryptAESGCM(plaintext: plaintext, key: key, nonce: nonce)
        return EncryptedMessage(
            nonce: nonce.base64EncodedString(),
            ciphertext: sealed.ciphertext.base64EncodedString(),
            tag: sealed.tag.base64EncodedString()
        )
    }

    public func decrypt(_ message: EncryptedMessage) throws -> InkMessage {
        let plaintext = try decryptData(message)
        return try JSONLineCodec.decodePayload(plaintext)
    }

    public func decryptData(_ message: EncryptedMessage) throws -> Data {
        guard let nonce = Data(base64Encoded: message.nonce),
              let ciphertext = Data(base64Encoded: message.ciphertext),
              let tag = Data(base64Encoded: message.tag) else {
            throw SecureChannelError.invalidEnvelope
        }
        return try SecureChannel.decryptAESGCM(ciphertext: ciphertext, tag: tag, key: key, nonce: nonce)
    }
}

public enum SecureChannel {
    public static let algorithm = "x25519+hkdf-sha256+aes-256-gcm"

    public static func makeHandshake() throws -> SecureHandshake {
        #if canImport(CryptoKit)
        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        return SecureHandshake(
            publicKey: privateKey.publicKey.rawRepresentation,
            privateKey: privateKey.rawRepresentation,
            nonce: try randomBytes(count: 16)
        )
        #elseif canImport(InkWandCryptoC)
        var publicKey = [UInt8](repeating: 0, count: 32)
        var privateKey = [UInt8](repeating: 0, count: 32)
        guard inkwand_x25519_generate(&publicKey, &privateKey) == 1 else {
            throw SecureChannelError.unavailable
        }
        return SecureHandshake(publicKey: Data(publicKey), privateKey: Data(privateKey), nonce: try randomBytes(count: 16))
        #else
        throw SecureChannelError.unavailable
        #endif
    }

    public static func authProof(token: String, serverID: String, clientID: String, publicKey: String, nonce: String) throws -> String {
        let payload = Data("InkWand auth v1|\(serverID)|\(clientID)|\(publicKey)|\(nonce)".utf8)
        return try hmacSHA256(key: Data(token.utf8), data: payload).base64EncodedString()
    }

    public static func verifyAuthProof(token: String, serverID: String, clientID: String, publicKey: String, nonce: String, proof: String) throws -> Bool {
        let expected = try authProof(token: token, serverID: serverID, clientID: clientID, publicKey: publicKey, nonce: nonce)
        return constantTimeEqual(Data(expected.utf8), Data(proof.utf8))
    }

    public static func makeClientSession(
        handshake: SecureHandshake,
        serverPublicKey: String,
        clientNonce: String,
        serverNonce: String,
        token: String?,
        context: String
    ) throws -> SecureSession {
        guard clientNonce == handshake.nonceString,
              let serverPublicKeyData = Data(base64Encoded: serverPublicKey),
              let serverNonceData = Data(base64Encoded: serverNonce) else {
            throw SecureChannelError.invalidKey
        }
        let shared = try sharedSecret(privateKey: handshake.privateKey, publicKey: serverPublicKeyData)
        let salt = handshake.nonce + serverNonceData + Data((token ?? "").utf8)
        let key = try hkdfSHA256(inputKeyMaterial: shared, salt: salt, info: Data(context.utf8), outputByteCount: 32)
        return SecureSession(key: key)
    }

    public static func makeServerSession(
        clientPublicKey: String,
        clientNonce: String,
        token: String?,
        context: String
    ) throws -> (session: SecureSession, publicKey: String, nonce: String) {
        guard let clientPublicKeyData = Data(base64Encoded: clientPublicKey),
              let clientNonceData = Data(base64Encoded: clientNonce) else {
            throw SecureChannelError.invalidKey
        }
        let handshake = try makeHandshake()
        let shared = try sharedSecret(privateKey: handshake.privateKey, publicKey: clientPublicKeyData)
        let salt = clientNonceData + handshake.nonce + Data((token ?? "").utf8)
        let key = try hkdfSHA256(inputKeyMaterial: shared, salt: salt, info: Data(context.utf8), outputByteCount: 32)
        return (SecureSession(key: key), handshake.publicKeyString, handshake.nonceString)
    }

    public static func randomBytes(count: Int) throws -> Data {
        #if canImport(Security)
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw SecureChannelError.unavailable
        }
        return Data(bytes)
        #elseif canImport(InkWandCryptoC)
        var bytes = [UInt8](repeating: 0, count: count)
        guard inkwand_random_bytes(&bytes, count) == 1 else {
            throw SecureChannelError.unavailable
        }
        return Data(bytes)
        #else
        var bytes = [UInt8](repeating: 0, count: count)
        for index in bytes.indices {
            bytes[index] = UInt8.random(in: 0...255)
        }
        return Data(bytes)
        #endif
    }

    static func hmacSHA256(key: Data, data: Data) throws -> Data {
        #if canImport(CryptoKit)
        let symmetricKey = SymmetricKey(data: key)
        return Data(HMAC<SHA256>.authenticationCode(for: data, using: symmetricKey))
        #elseif canImport(InkWandCryptoC)
        var out = [UInt8](repeating: 0, count: 32)
        let ok = key.withUnsafeBytes { keyBuffer in
            data.withUnsafeBytes { dataBuffer in
                inkwand_hmac_sha256(
                    keyBuffer.bindMemory(to: UInt8.self).baseAddress,
                    key.count,
                    dataBuffer.bindMemory(to: UInt8.self).baseAddress,
                    data.count,
                    &out
                )
            }
        }
        guard ok == 1 else { throw SecureChannelError.unavailable }
        return Data(out)
        #else
        throw SecureChannelError.unavailable
        #endif
    }

    private static func hkdfSHA256(inputKeyMaterial: Data, salt: Data, info: Data, outputByteCount: Int) throws -> Data {
        let prk = try hmacSHA256(key: salt, data: inputKeyMaterial)
        var output = Data()
        var previous = Data()
        var counter: UInt8 = 1
        while output.count < outputByteCount {
            var blockInput = Data()
            blockInput.append(previous)
            blockInput.append(info)
            blockInput.append(counter)
            previous = try hmacSHA256(key: prk, data: blockInput)
            output.append(previous)
            counter &+= 1
        }
        return Data(output.prefix(outputByteCount))
    }

    private static func sharedSecret(privateKey: Data, publicKey: Data) throws -> Data {
        guard privateKey.count == 32, publicKey.count == 32 else {
            throw SecureChannelError.invalidKey
        }
        #if canImport(CryptoKit)
        let privateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privateKey)
        let publicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: publicKey)
        return try privateKey.sharedSecretFromKeyAgreement(with: publicKey).withUnsafeBytes { Data($0) }
        #elseif canImport(InkWandCryptoC)
        var out = [UInt8](repeating: 0, count: 32)
        var privateBytes = [UInt8](privateKey)
        var publicBytes = [UInt8](publicKey)
        guard inkwand_x25519_shared(&privateBytes, &publicBytes, &out) == 1 else {
            throw SecureChannelError.invalidKey
        }
        return Data(out)
        #else
        throw SecureChannelError.unavailable
        #endif
    }

    fileprivate static func encryptAESGCM(plaintext: Data, key: Data, nonce: Data) throws -> (ciphertext: Data, tag: Data) {
        guard key.count == 32, nonce.count == 12 else { throw SecureChannelError.invalidKey }
        #if canImport(CryptoKit)
        let sealed = try AES.GCM.seal(plaintext, using: SymmetricKey(data: key), nonce: AES.GCM.Nonce(data: nonce))
        return (sealed.ciphertext, sealed.tag)
        #elseif canImport(InkWandCryptoC)
        var ciphertext = [UInt8](repeating: 0, count: plaintext.count)
        var tag = [UInt8](repeating: 0, count: 16)
        var keyBytes = [UInt8](key)
        var nonceBytes = [UInt8](nonce)
        let ok = plaintext.withUnsafeBytes { plaintextBuffer in
            inkwand_aes_256_gcm_encrypt(
                &keyBytes,
                &nonceBytes,
                plaintextBuffer.bindMemory(to: UInt8.self).baseAddress,
                plaintext.count,
                &ciphertext,
                &tag
            )
        }
        guard ok == 1 else { throw SecureChannelError.unavailable }
        return (Data(ciphertext), Data(tag))
        #else
        throw SecureChannelError.unavailable
        #endif
    }

    fileprivate static func decryptAESGCM(ciphertext: Data, tag: Data, key: Data, nonce: Data) throws -> Data {
        guard key.count == 32, nonce.count == 12, tag.count == 16 else { throw SecureChannelError.invalidKey }
        #if canImport(CryptoKit)
        let sealed = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: nonce), ciphertext: ciphertext, tag: tag)
        return try AES.GCM.open(sealed, using: SymmetricKey(data: key))
        #elseif canImport(InkWandCryptoC)
        var plaintext = [UInt8](repeating: 0, count: ciphertext.count)
        var keyBytes = [UInt8](key)
        var nonceBytes = [UInt8](nonce)
        var tagBytes = [UInt8](tag)
        let ok = ciphertext.withUnsafeBytes { ciphertextBuffer in
            inkwand_aes_256_gcm_decrypt(
                &keyBytes,
                &nonceBytes,
                ciphertextBuffer.bindMemory(to: UInt8.self).baseAddress,
                ciphertext.count,
                &tagBytes,
                &plaintext
            )
        }
        guard ok == 1 else { throw SecureChannelError.authenticationFailed }
        return Data(plaintext)
        #else
        throw SecureChannelError.unavailable
        #endif
    }

    private static func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for (left, right) in zip(lhs, rhs) {
            difference |= left ^ right
        }
        return difference == 0
    }
}
