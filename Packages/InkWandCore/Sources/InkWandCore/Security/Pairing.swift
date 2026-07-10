import Foundation
#if canImport(Security)
import Security
#endif

public struct ServerAdvertisement: Codable, Equatable, Sendable, Identifiable {
    public var id: String { serverID }
    public var serverID: String
    public var name: String
    public var port: UInt16
    public var protocolVersion: Int
    public var pairingAvailable: Bool

    public init(
        serverID: String,
        name: String,
        port: UInt16,
        protocolVersion: Int = inkWandProtocolVersion,
        pairingAvailable: Bool
    ) {
        self.serverID = serverID
        self.name = name
        self.port = port
        self.protocolVersion = protocolVersion
        self.pairingAvailable = pairingAvailable
    }
}

public struct PairingRequest: Codable, Equatable, Sendable {
    public var serverID: String
    public var clientID: String
    public var clientName: String
    public var code: String
    public var clientPublicKey: String?
    public var clientNonce: String?

    public init(
        serverID: String,
        clientID: String,
        clientName: String,
        code: String,
        clientPublicKey: String? = nil,
        clientNonce: String? = nil
    ) {
        self.serverID = serverID
        self.clientID = clientID
        self.clientName = clientName
        self.code = code
        self.clientPublicKey = clientPublicKey
        self.clientNonce = clientNonce
    }
}

public struct PairingResponse: Codable, Equatable, Sendable {
    public var accepted: Bool
    public var serverID: String
    public var serverName: String
    public var clientID: String
    public var trustToken: String?
    public var encryptedTrustToken: String?
    public var serverPublicKey: String?
    public var serverNonce: String?
    public var error: String?

    public init(
        accepted: Bool,
        serverID: String,
        serverName: String,
        clientID: String,
        trustToken: String?,
        encryptedTrustToken: String? = nil,
        serverPublicKey: String? = nil,
        serverNonce: String? = nil,
        error: String?
    ) {
        self.accepted = accepted
        self.serverID = serverID
        self.serverName = serverName
        self.clientID = clientID
        self.trustToken = trustToken
        self.encryptedTrustToken = encryptedTrustToken
        self.serverPublicKey = serverPublicKey
        self.serverNonce = serverNonce
        self.error = error
    }
}

public struct AuthRequest: Codable, Equatable, Sendable {
    public var serverID: String
    public var clientID: String
    public var clientName: String
    public var trustToken: String
    public var clientPublicKey: String?
    public var clientNonce: String?
    public var authProof: String?

    public init(
        serverID: String,
        clientID: String,
        clientName: String,
        trustToken: String,
        clientPublicKey: String? = nil,
        clientNonce: String? = nil,
        authProof: String? = nil
    ) {
        self.serverID = serverID
        self.clientID = clientID
        self.clientName = clientName
        self.trustToken = trustToken
        self.clientPublicKey = clientPublicKey
        self.clientNonce = clientNonce
        self.authProof = authProof
    }
}

public struct AuthResponse: Codable, Equatable, Sendable {
    public var accepted: Bool
    public var serverID: String
    public var serverPublicKey: String?
    public var serverNonce: String?
    public var error: String?

    public init(
        accepted: Bool,
        serverID: String,
        serverPublicKey: String? = nil,
        serverNonce: String? = nil,
        error: String?
    ) {
        self.accepted = accepted
        self.serverID = serverID
        self.serverPublicKey = serverPublicKey
        self.serverNonce = serverNonce
        self.error = error
    }
}

public struct TrustedPeer: Codable, Equatable, Sendable, Identifiable {
    public var id: String { peerID }
    public var peerID: String
    public var name: String
    public var trustToken: String
    public var createdAt: Date
    public var lastSeenAt: Date?

    public init(peerID: String, name: String, trustToken: String, createdAt: Date = Date(), lastSeenAt: Date? = nil) {
        self.peerID = peerID
        self.name = name
        self.trustToken = trustToken
        self.createdAt = createdAt
        self.lastSeenAt = lastSeenAt
    }
}

public struct TrustStoreSnapshot: Codable, Equatable, Sendable {
    public var localID: String
    public var localName: String
    public var trustedPeers: [TrustedPeer]

    public init(localID: String = UUID().uuidString, localName: String, trustedPeers: [TrustedPeer] = []) {
        self.localID = localID
        self.localName = localName
        self.trustedPeers = trustedPeers
    }
}

public enum TrustStoreError: Error, Equatable {
    case peerNotFound
    case invalidToken
}

public final class TrustStore: @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()
    private var snapshot: TrustStoreSnapshot

    public init(url: URL, defaultLocalName: String) throws {
        self.url = url
        if let data = try? Data(contentsOf: url) {
            snapshot = try JSONDecoder().decode(TrustStoreSnapshot.self, from: data)
            if snapshot.localName.isEmpty {
                snapshot.localName = defaultLocalName
            }
        } else {
            snapshot = TrustStoreSnapshot(localName: defaultLocalName)
        }
    }

    public var localID: String {
        lock.withLock { snapshot.localID }
    }

    public var localName: String {
        get { lock.withLock { snapshot.localName } }
        set {
            lock.withLock {
                snapshot.localName = newValue
                try? saveLocked()
            }
        }
    }

    public func allPeers() -> [TrustedPeer] {
        lock.withLock { snapshot.trustedPeers.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } }
    }

    public func peer(peerID: String) throws -> TrustedPeer {
        try lock.withLock {
            guard let peer = snapshot.trustedPeers.first(where: { $0.peerID == peerID }) else {
                throw TrustStoreError.peerNotFound
            }
            return peer
        }
    }

    @discardableResult
    public func trustPeer(peerID: String, name: String, token: String, now: Date = Date()) throws -> TrustedPeer {
        guard !token.isEmpty else { throw TrustStoreError.invalidToken }
        return try lock.withLock {
            let peer = TrustedPeer(peerID: peerID, name: name, trustToken: token, createdAt: now)
            if let index = snapshot.trustedPeers.firstIndex(where: { $0.peerID == peerID }) {
                snapshot.trustedPeers[index] = peer
            } else {
                snapshot.trustedPeers.append(peer)
            }
            try saveLocked()
            return peer
        }
    }

    public func validate(peerID: String, token: String, now: Date = Date()) throws -> TrustedPeer {
        try lock.withLock {
            guard let index = snapshot.trustedPeers.firstIndex(where: { $0.peerID == peerID }) else {
                throw TrustStoreError.peerNotFound
            }
            guard snapshot.trustedPeers[index].trustToken == token, !token.isEmpty else {
                throw TrustStoreError.invalidToken
            }
            snapshot.trustedPeers[index].lastSeenAt = now
            try saveLocked()
            return snapshot.trustedPeers[index]
        }
    }

    public func revoke(peerID: String) throws {
        try lock.withLock {
            snapshot.trustedPeers.removeAll { $0.peerID == peerID }
            try saveLocked()
        }
    }

    private func saveLocked() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(snapshot).write(to: url, options: [.atomic])
    }
}

public struct ActivePairingCode: Equatable, Sendable {
    public var code: String
    public var expiresAt: Date
}

public struct PendingPairingRequest: Equatable, Sendable, Identifiable {
    public var id: String { requestID }
    public var requestID: String
    public var clientID: String
    public var clientName: String
    public var requestedAt: Date
    public var expiresAt: Date

    public init(requestID: String, clientID: String, clientName: String, requestedAt: Date, expiresAt: Date) {
        self.requestID = requestID
        self.clientID = clientID
        self.clientName = clientName
        self.requestedAt = requestedAt
        self.expiresAt = expiresAt
    }
}

public enum PairingManagerError: Error, Equatable {
    case noActiveCode
    case expiredCode
    case invalidCode
    case wrongServer
    case tooManyAttempts
    case pendingRequestNotFound
    case rejected
}

public final class PairingManager: @unchecked Sendable {
    private let lock = NSLock()
    private let store: TrustStore
    private let maxAttempts: Int
    private var activeCode: ActivePairingCode?
    private var failedAttempts: [String: Int] = [:]
    private var pendingRequests: [String: PendingPairingRequest] = [:]
    private var pendingRequestPayloads: [String: PairingRequest] = [:]
    private var pendingDecisions: [String: PairingResponse] = [:]
    private var pendingSecureSessions: [String: SecureSession] = [:]

    public init(store: TrustStore, maxAttempts: Int = 5) {
        self.store = store
        self.maxAttempts = maxAttempts
    }

    public func beginPairing(now: Date = Date(), lifetime: TimeInterval = 120) -> ActivePairingCode {
        lock.withLock {
            failedAttempts.removeAll()
            let code = String(format: "%06d", Int.random(in: 0...999_999))
            let active = ActivePairingCode(code: code, expiresAt: now.addingTimeInterval(lifetime))
            activeCode = active
            return active
        }
    }

    public func cancelPairing() {
        lock.withLock {
            activeCode = nil
            failedAttempts.removeAll()
            pendingRequests.removeAll()
            pendingRequestPayloads.removeAll()
            pendingDecisions.removeAll()
            pendingSecureSessions.removeAll()
        }
    }

    public func isPairingAvailable(now: Date = Date()) -> Bool {
        lock.withLock {
            guard let activeCode else { return false }
            return activeCode.expiresAt > now
        }
    }

    public func accept(_ request: PairingRequest, now: Date = Date()) throws -> PairingResponse {
        let token = Self.makeToken()
        return try lock.withLock {
            guard request.serverID.isEmpty || request.serverID == store.localID else {
                throw PairingManagerError.wrongServer
            }
            guard let activeCode else {
                throw PairingManagerError.noActiveCode
            }
            guard activeCode.expiresAt > now else {
                self.activeCode = nil
                throw PairingManagerError.expiredCode
            }
            let attempts = failedAttempts[request.clientID, default: 0]
            guard attempts < maxAttempts else {
                throw PairingManagerError.tooManyAttempts
            }
            guard request.code == activeCode.code else {
                failedAttempts[request.clientID] = attempts + 1
                throw PairingManagerError.invalidCode
            }

            self.activeCode = nil
            failedAttempts.removeAll()
            try store.trustPeer(peerID: request.clientID, name: request.clientName, token: token, now: now)
            return PairingResponse(
                accepted: true,
                serverID: store.localID,
                serverName: store.localName,
                clientID: request.clientID,
                trustToken: token,
                error: nil
            )
        }
    }

    public func requestApproval(_ request: PairingRequest, now: Date = Date(), lifetime: TimeInterval = 120) throws -> PendingPairingRequest {
        try lock.withLock {
            guard request.serverID.isEmpty || request.serverID == store.localID else {
                throw PairingManagerError.wrongServer
            }

            removeExpiredPendingRequestsLocked(now: now)

            if let existing = pendingRequests.values.first(where: { $0.clientID == request.clientID }) {
                pendingRequestPayloads[existing.requestID] = request
                return existing
            }

            let pending = PendingPairingRequest(
                requestID: UUID().uuidString,
                clientID: request.clientID,
                clientName: request.clientName,
                requestedAt: now,
                expiresAt: now.addingTimeInterval(lifetime)
            )
            pendingRequests[pending.requestID] = pending
            pendingRequestPayloads[pending.requestID] = request
            return pending
        }
    }

    public func pendingApprovals(now: Date = Date()) -> [PendingPairingRequest] {
        lock.withLock {
            removeExpiredPendingRequestsLocked(now: now)
            return pendingRequests.values.sorted { $0.requestedAt < $1.requestedAt }
        }
    }

    @discardableResult
    public func approvePending(requestID: String, now: Date = Date()) throws -> PairingResponse {
        let token = Self.makeToken()
        return try lock.withLock {
            removeExpiredPendingRequestsLocked(now: now)
            guard let pending = pendingRequests.removeValue(forKey: requestID),
                  let request = pendingRequestPayloads.removeValue(forKey: requestID) else {
                throw PairingManagerError.pendingRequestNotFound
            }
            guard pending.expiresAt > now else {
                throw PairingManagerError.expiredCode
            }

            try store.trustPeer(peerID: request.clientID, name: request.clientName, token: token, now: now)
            let response = PairingResponse(
                accepted: true,
                serverID: store.localID,
                serverName: store.localName,
                clientID: request.clientID,
                trustToken: token,
                error: nil
            )
            pendingDecisions[requestID] = response
            return response
        }
    }

    @discardableResult
    public func rejectPending(requestID: String, reason: String = "Pairing rejected on the computer", now: Date = Date()) throws -> PairingResponse {
        try lock.withLock {
            removeExpiredPendingRequestsLocked(now: now)
            guard let pending = pendingRequests.removeValue(forKey: requestID),
                  let request = pendingRequestPayloads.removeValue(forKey: requestID) else {
                throw PairingManagerError.pendingRequestNotFound
            }
            let response = PairingResponse(
                accepted: false,
                serverID: store.localID,
                serverName: store.localName,
                clientID: request.clientID,
                trustToken: nil,
                error: pending.expiresAt <= now ? "Pairing request expired" : reason
            )
            pendingDecisions[requestID] = response
            return response
        }
    }

    public func waitForPendingDecision(requestID: String, now: @escaping () -> Date = Date.init) -> PairingResponse {
        while true {
            if let response = lock.withLock({ pendingDecisions.removeValue(forKey: requestID) }) {
                return response
            }

            let expiredResponse = lock.withLock { () -> PairingResponse? in
                guard let pending = pendingRequests[requestID], pending.expiresAt <= now() else {
                    return nil
                }
                pendingRequests.removeValue(forKey: requestID)
                let request = pendingRequestPayloads.removeValue(forKey: requestID)
                return PairingResponse(
                    accepted: false,
                    serverID: store.localID,
                    serverName: store.localName,
                    clientID: request?.clientID ?? pending.clientID,
                    trustToken: nil,
                    error: "Pairing request expired"
                )
            }
            if let expiredResponse {
                return expiredResponse
            }

            if lock.withLock({ pendingRequests[requestID] == nil }) {
                return PairingResponse(
                    accepted: false,
                    serverID: store.localID,
                    serverName: store.localName,
                    clientID: "",
                    trustToken: nil,
                    error: "Pairing request is no longer available"
                )
            }

            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    public func authenticate(_ request: AuthRequest, now: Date = Date()) throws -> TrustedPeer {
        guard request.serverID == store.localID else {
            throw PairingManagerError.wrongServer
        }
        return try store.validate(peerID: request.clientID, token: request.trustToken, now: now)
    }

    public func authenticateSecure(_ request: AuthRequest, now: Date = Date()) throws -> (AuthResponse, SecureSession?) {
        guard request.serverID == store.localID else {
            throw PairingManagerError.wrongServer
        }

        guard let clientPublicKey = request.clientPublicKey,
              let clientNonce = request.clientNonce,
              let proof = request.authProof else {
            _ = try store.validate(peerID: request.clientID, token: request.trustToken, now: now)
            return (AuthResponse(accepted: true, serverID: store.localID, error: nil), nil)
        }

        let peer = try store.peer(peerID: request.clientID)
        guard try SecureChannel.verifyAuthProof(
            token: peer.trustToken,
            serverID: store.localID,
            clientID: request.clientID,
            publicKey: clientPublicKey,
            nonce: clientNonce,
            proof: proof
        ) else {
            throw TrustStoreError.invalidToken
        }
        _ = try store.validate(peerID: request.clientID, token: peer.trustToken, now: now)

        let established = try SecureChannel.makeServerSession(
            clientPublicKey: clientPublicKey,
            clientNonce: clientNonce,
            token: peer.trustToken,
            context: "InkWand auth v1|\(store.localID)|\(request.clientID)"
        )
        return (
            AuthResponse(
                accepted: true,
                serverID: store.localID,
                serverPublicKey: established.publicKey,
                serverNonce: established.nonce,
                error: nil
            ),
            established.session
        )
    }

    @discardableResult
    public func approvePendingSecure(requestID: String, now: Date = Date()) throws -> (PairingResponse, SecureSession?) {
        let token = Self.makeToken()
        return try lock.withLock {
            removeExpiredPendingRequestsLocked(now: now)
            guard let pending = pendingRequests.removeValue(forKey: requestID),
                  let request = pendingRequestPayloads.removeValue(forKey: requestID) else {
                throw PairingManagerError.pendingRequestNotFound
            }
            guard pending.expiresAt > now else {
                throw PairingManagerError.expiredCode
            }

            let established: (session: SecureSession, publicKey: String, nonce: String)?
            let encryptedToken: String?
            if let clientPublicKey = request.clientPublicKey, let clientNonce = request.clientNonce {
                let secure = try SecureChannel.makeServerSession(
                    clientPublicKey: clientPublicKey,
                    clientNonce: clientNonce,
                    token: nil,
                    context: "InkWand pairing v1|\(store.localID)|\(request.clientID)"
                )
                let envelope = try secure.session.encryptData(Data(token.utf8))
                encryptedToken = try String(data: JSONEncoder().encode(envelope), encoding: .utf8)
                established = secure
            } else {
                encryptedToken = nil
                established = nil
            }

            try store.trustPeer(peerID: request.clientID, name: request.clientName, token: token, now: now)
            let response = PairingResponse(
                accepted: true,
                serverID: store.localID,
                serverName: store.localName,
                clientID: request.clientID,
                trustToken: encryptedToken == nil ? token : nil,
                encryptedTrustToken: encryptedToken,
                serverPublicKey: established?.publicKey,
                serverNonce: established?.nonce,
                error: nil
            )
            pendingDecisions[requestID] = response
            if let session = established?.session {
                pendingSecureSessions[requestID] = session
            }
            return (response, established?.session)
        }
    }

    public func takePendingSecureSession(requestID: String) -> SecureSession? {
        lock.withLock {
            pendingSecureSessions.removeValue(forKey: requestID)
        }
    }

    private static func makeToken(byteCount: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        #if canImport(Security)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        #else
        for index in bytes.indices {
            bytes[index] = UInt8.random(in: UInt8.min...UInt8.max)
        }
        #endif
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private func removeExpiredPendingRequestsLocked(now: Date) {
        let expiredIDs = pendingRequests.compactMap { requestID, pending in
            pending.expiresAt <= now ? requestID : nil
        }
        expiredIDs.forEach {
            if let request = pendingRequestPayloads[$0] {
                pendingDecisions[$0] = PairingResponse(
                    accepted: false,
                    serverID: store.localID,
                    serverName: store.localName,
                    clientID: request.clientID,
                    trustToken: nil,
                    error: "Pairing request expired"
                )
            }
            pendingRequests.removeValue(forKey: $0)
            pendingRequestPayloads.removeValue(forKey: $0)
            pendingSecureSessions.removeValue(forKey: $0)
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
