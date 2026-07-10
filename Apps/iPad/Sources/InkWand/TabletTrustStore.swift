#if canImport(UIKit)
import Foundation
import InkWandCore

final class TabletTrustStore: @unchecked Sendable {
    private static let clientIDKey = "InkWand.ClientID"
    private static let clientNameKey = "InkWand.ClientName"
    private static let peersKey = "InkWand.TrustedServers"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var clientID: String {
        if let existing = defaults.string(forKey: Self.clientIDKey) {
            return existing
        }
        let generated = UUID().uuidString
        defaults.set(generated, forKey: Self.clientIDKey)
        return generated
    }

    var clientName: String {
        get {
            defaults.string(forKey: Self.clientNameKey) ?? "iPad"
        }
        set {
            defaults.set(newValue, forKey: Self.clientNameKey)
        }
    }

    func allServers() -> [TrustedPeer] {
        guard let data = defaults.data(forKey: Self.peersKey),
              let peers = try? JSONDecoder().decode([TrustedPeer].self, from: data) else {
            return []
        }
        return peers
    }

    func server(id: String) -> TrustedPeer? {
        allServers().first { $0.peerID == id }
    }

    func server(named name: String) -> TrustedPeer? {
        allServers().first { $0.name == name }
    }

    func trust(serverID: String, name: String, token: String) {
        var peers = allServers().filter { $0.peerID != serverID }
        peers.append(TrustedPeer(peerID: serverID, name: name, trustToken: token))
        if let data = try? JSONEncoder().encode(peers) {
            defaults.set(data, forKey: Self.peersKey)
        }
    }

    func revoke(serverID: String) {
        let peers = allServers().filter { $0.peerID != serverID }
        if let data = try? JSONEncoder().encode(peers) {
            defaults.set(data, forKey: Self.peersKey)
        }
    }

    func revokeAll() {
        defaults.removeObject(forKey: Self.peersKey)
    }
}
#endif
