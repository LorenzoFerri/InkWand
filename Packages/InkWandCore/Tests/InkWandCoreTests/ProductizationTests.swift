import XCTest
@testable import InkWandCore

final class ProductizationTests: XCTestCase {
    func testPairingMessagesRoundTrip() throws {
        let request = PairingRequest(serverID: "server", clientID: "ipad", clientName: "Studio iPad", code: "123456")
        let response = PairingResponse(
            accepted: true,
            serverID: "server",
            serverName: "Linux Workstation",
            clientID: "ipad",
            trustToken: "token",
            error: nil
        )

        XCTAssertEqual(try JSONLineCodec.decodeLine(try JSONLineCodec.encode(.pairingRequest(request))), .pairingRequest(request))
        XCTAssertEqual(try JSONLineCodec.decodeLine(try JSONLineCodec.encode(.pairingResponse(response))), .pairingResponse(response))
    }

    func testAuthMessagesRoundTrip() throws {
        let request = AuthRequest(serverID: "server", clientID: "ipad", clientName: "Studio iPad", trustToken: "token")
        let response = AuthResponse(accepted: true, serverID: "server", error: nil)

        XCTAssertEqual(try JSONLineCodec.decodeLine(try JSONLineCodec.encode(.authRequest(request))), .authRequest(request))
        XCTAssertEqual(try JSONLineCodec.decodeLine(try JSONLineCodec.encode(.authResponse(response))), .authResponse(response))
    }

    func testSecureChannelEncryptsMessagesAndVerifiesAuthProof() throws {
        let token = "shared-secret-token"
        let clientID = "ipad"
        let serverID = "server"
        let context = "InkWand auth v1|\(serverID)|\(clientID)"
        let clientHandshake = try SecureChannel.makeHandshake()
        let server = try SecureChannel.makeServerSession(
            clientPublicKey: clientHandshake.publicKeyString,
            clientNonce: clientHandshake.nonceString,
            token: token,
            context: context
        )
        let clientSession = try SecureChannel.makeClientSession(
            handshake: clientHandshake,
            serverPublicKey: server.publicKey,
            clientNonce: clientHandshake.nonceString,
            serverNonce: server.nonce,
            token: token,
            context: context
        )

        let encrypted = try clientSession.encrypt(.pad(.undo))
        XCTAssertEqual(try server.session.decrypt(encrypted), .pad(.undo))

        let proof = try SecureChannel.authProof(
            token: token,
            serverID: serverID,
            clientID: clientID,
            publicKey: clientHandshake.publicKeyString,
            nonce: clientHandshake.nonceString
        )
        XCTAssertTrue(try SecureChannel.verifyAuthProof(
            token: token,
            serverID: serverID,
            clientID: clientID,
            publicKey: clientHandshake.publicKeyString,
            nonce: clientHandshake.nonceString,
            proof: proof
        ))
        XCTAssertFalse(try SecureChannel.verifyAuthProof(
            token: "wrong-token",
            serverID: serverID,
            clientID: clientID,
            publicKey: clientHandshake.publicKeyString,
            nonce: clientHandshake.nonceString,
            proof: proof
        ))
    }

    func testTrustStoreCreatesValidatesAndRevokesPeer() throws {
        let directory = try temporaryDirectory()
        let store = try TrustStore(url: directory.appendingPathComponent("trust.json"), defaultLocalName: "Server")

        try store.trustPeer(peerID: "ipad", name: "iPad", token: "token")
        XCTAssertEqual(try store.validate(peerID: "ipad", token: "token").peerID, "ipad")

        try store.revoke(peerID: "ipad")
        XCTAssertThrowsError(try store.validate(peerID: "ipad", token: "token")) { error in
            XCTAssertEqual(error as? TrustStoreError, .peerNotFound)
        }
    }

    func testPairingRejectsExpiredWrongAndReplayedCodes() throws {
        let directory = try temporaryDirectory()
        let store = try TrustStore(url: directory.appendingPathComponent("trust.json"), defaultLocalName: "Server")
        let manager = PairingManager(store: store, maxAttempts: 1)
        let now = Date(timeIntervalSince1970: 100)
        let active = manager.beginPairing(now: now, lifetime: 10)

        XCTAssertThrowsError(
            try manager.accept(PairingRequest(serverID: store.localID, clientID: "ipad", clientName: "iPad", code: "000000"), now: now)
        ) { error in
            XCTAssertEqual(error as? PairingManagerError, .invalidCode)
        }

        XCTAssertThrowsError(
            try manager.accept(PairingRequest(serverID: store.localID, clientID: "ipad", clientName: "iPad", code: active.code), now: now)
        ) { error in
            XCTAssertEqual(error as? PairingManagerError, .tooManyAttempts)
        }

        let refreshed = manager.beginPairing(now: now, lifetime: 1)
        XCTAssertThrowsError(
            try manager.accept(PairingRequest(serverID: store.localID, clientID: "other", clientName: "iPad", code: refreshed.code), now: now.addingTimeInterval(2))
        ) { error in
            XCTAssertEqual(error as? PairingManagerError, .expiredCode)
        }

        let valid = manager.beginPairing(now: now, lifetime: 10)
        let response = try manager.accept(
            PairingRequest(serverID: store.localID, clientID: "ipad", clientName: "iPad", code: valid.code),
            now: now
        )
        XCTAssertTrue(response.accepted)
        XCTAssertNotNil(response.trustToken)

        XCTAssertThrowsError(
            try manager.accept(PairingRequest(serverID: store.localID, clientID: "ipad2", clientName: "iPad", code: valid.code), now: now)
        ) { error in
            XCTAssertEqual(error as? PairingManagerError, .noActiveCode)
        }
    }

    func testPairingApprovalRequestCreatesTrustOrRejects() throws {
        let directory = try temporaryDirectory()
        let store = try TrustStore(url: directory.appendingPathComponent("trust.json"), defaultLocalName: "Server")
        let manager = PairingManager(store: store)
        let now = Date(timeIntervalSince1970: 200)

        let pending = try manager.requestApproval(
            PairingRequest(serverID: store.localID, clientID: "ipad", clientName: "Studio iPad", code: ""),
            now: now
        )
        XCTAssertEqual(manager.pendingApprovals(now: now), [pending])

        let approved = try manager.approvePending(requestID: pending.requestID, now: now)
        XCTAssertTrue(approved.accepted)
        XCTAssertEqual(approved.clientID, "ipad")
        XCTAssertNotNil(approved.trustToken)
        XCTAssertEqual(try store.validate(peerID: "ipad", token: approved.trustToken ?? "").name, "Studio iPad")
        XCTAssertEqual(manager.waitForPendingDecision(requestID: pending.requestID).accepted, true)

        let rejected = try manager.requestApproval(
            PairingRequest(serverID: store.localID, clientID: "ipad2", clientName: "Kitchen iPad", code: ""),
            now: now
        )
        try manager.rejectPending(requestID: rejected.requestID, now: now)
        let rejectedResponse = manager.waitForPendingDecision(requestID: rejected.requestID)
        XCTAssertFalse(rejectedResponse.accepted)
        XCTAssertNil(rejectedResponse.trustToken)
    }

    func testPadBindingValidationAndStore() throws {
        let directory = try temporaryDirectory()
        let store = try PadBindingStore(url: directory.appendingPathComponent("bindings.json"))
        XCTAssertEqual(store.load(), .default)

        let map = PadBindingMap(bindings: [.undo: KeyStroke(keyCodes: [1, 2, 3])])
        XCTAssertNoThrow(try map.validating(allowedKeyCodes: 1...10))
        XCTAssertThrowsError(try map.validating(allowedKeyCodes: 4...10)) { error in
            XCTAssertEqual(error as? PadBindingError, .unsupportedKeyCode(1))
        }

        try store.save(map)
        XCTAssertEqual(try PadBindingStore(url: directory.appendingPathComponent("bindings.json")).load(), map)
        try store.reset()
        XCTAssertEqual(store.load(), .default)
    }

    func testAutostartCreateRemoveAndStaleDetection() throws {
        let directory = try temporaryDirectory()
        let fileURL = directory.appendingPathComponent("inkwand.desktop")
        let manager = AutostartManager(fileURL: fileURL)

        XCTAssertEqual(manager.state(expectedAppImagePath: "/tmp/InkWand.AppImage"), .disabled)

        try manager.enable(appImagePath: "/tmp/InkWand.AppImage")
        XCTAssertEqual(manager.state(expectedAppImagePath: "/tmp/InkWand.AppImage"), .enabled(path: "/tmp/InkWand.AppImage"))
        XCTAssertEqual(
            manager.state(expectedAppImagePath: "/opt/InkWand.AppImage"),
            .stale(path: "/tmp/InkWand.AppImage", expectedPath: "/opt/InkWand.AppImage")
        )

        try manager.disable()
        XCTAssertEqual(manager.state(expectedAppImagePath: "/tmp/InkWand.AppImage"), .disabled)
    }

    func testDefaultProductPathsUsePlatformConventions() {
        let paths = ProductPaths.default
        #if os(macOS)
        XCTAssertTrue(paths.configDirectory.path.contains("Library/Application Support/InkWand"))
        XCTAssertEqual(paths.configDirectory, paths.dataDirectory)
        #else
        XCTAssertTrue(paths.configDirectory.path.hasSuffix(".config/inkwand") || paths.configDirectory.path.contains("/inkwand"))
        XCTAssertTrue(paths.dataDirectory.path.hasSuffix(".local/share/inkwand") || paths.dataDirectory.path.contains("/inkwand"))
        #endif
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
