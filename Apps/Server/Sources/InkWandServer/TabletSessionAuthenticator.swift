import Foundation
import InkWandCore

final class TabletSessionAuthenticator: @unchecked Sendable {
    private let pairingManager: PairingManager
    private let trustStore: TrustStore
    var onPairingRequestsChanged: (() -> Void)?

    init(pairingManager: PairingManager, trustStore: TrustStore) {
        self.pairingManager = pairingManager
        self.trustStore = trustStore
    }

    var serverID: String {
        trustStore.localID
    }

    var serverName: String {
        trustStore.localName
    }

    var pairingAvailable: Bool {
        pairingManager.isPairingAvailable()
    }

    func handlePreflight(_ message: InkMessage, client: TabletClient) throws -> Bool {
        switch message {
        case let .authRequest(request):
            do {
                let (response, secureSession) = try pairingManager.authenticateSecure(request)
                try client.sendMessage(.authResponse(response), encrypted: false)
                client.secureSession = secureSession
                return true
            } catch {
                try client.sendMessage(.authResponse(AuthResponse(accepted: false, serverID: trustStore.localID, error: String(describing: error))), encrypted: false)
                return false
            }

        case let .pairingRequest(request):
            do {
                var response: PairingResponse
                if request.code.isEmpty {
                    let pending = try pairingManager.requestApproval(request)
                    onPairingRequestsChanged?()
                    response = pairingManager.waitForPendingDecision(requestID: pending.requestID)
                    client.secureSession = pairingManager.takePendingSecureSession(requestID: pending.requestID)
                    onPairingRequestsChanged?()
                } else {
                    response = try pairingManager.accept(request)
                }
                try client.sendMessage(.pairingResponse(response), encrypted: false)
                return response.accepted
            } catch {
                try client.sendMessage(
                    .pairingResponse(
                        PairingResponse(
                            accepted: false,
                            serverID: trustStore.localID,
                            serverName: trustStore.localName,
                            clientID: request.clientID,
                            trustToken: nil,
                            error: String(describing: error)
                        )
                    ),
                    encrypted: false
                )
                return false
            }

        default:
            return false
        }
    }
}
