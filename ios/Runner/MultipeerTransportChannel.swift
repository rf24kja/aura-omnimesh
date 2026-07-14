// ios/Runner/MultipeerTransportChannel.swift
//
// Native side of:
//   FlutterMethodChannel("aura.omnimesh/transport")
//   FlutterEventChannel("aura.omnimesh/transport_events")
// Radio: Multipeer Connectivity (peer Wi-Fi + Bluetooth, fully offline).
//
// Info.plist prerequisites (iOS 14+ local network privacy):
//   NSLocalNetworkUsageDescription = "Discovers nearby Aura mesh nodes."
//   NSBonjourServices = ["_aura-omnimesh._tcp", "_aura-omnimesh._udp"]
//
// MTU note: MCSession fragments and reassembles arbitrarily large Data
// internally (.reliable mode), so unlike the Android Nearby path, no
// manual chunk framing is required — the whole payload string travels as
// one Data. The Dart contract ("chunking is native's job") is satisfied
// by the OS here.
//
// Double-connect prevention (mirror of Android): both peers see each
// other via advertise+browse; only the lexicographically SMALLER public
// key sends the invitation. The invitation context carries "pk|alias" so
// the advertiser side learns the inviter's identity before accepting.
//
// PLATFORM REALITY FLAG: Multipeer is Apple-only and Google Nearby is
// Android-only — the two do NOT interoperate over the air. Same-OS
// clusters mesh directly; cross-OS traffic transits a Core Node's
// Dart WebSocket bridge over shared LAN. This is an API-ecosystem
// constraint, not an architecture defect.

import Flutter
import Foundation
import MultipeerConnectivity

final class MultipeerTransportChannel: NSObject, FlutterStreamHandler {

    static let methodName = "aura.omnimesh/transport"
    static let eventName = "aura.omnimesh/transport_events"
    private static let serviceType = "aura-omnimesh" // <=15 chars, valid set.

    static func register(with messenger: FlutterBinaryMessenger)
        -> MultipeerTransportChannel
    {
        let instance = MultipeerTransportChannel()
        let methods = FlutterMethodChannel(
            name: methodName, binaryMessenger: messenger)
        methods.setMethodCallHandler(instance.handle)
        let events = FlutterEventChannel(
            name: eventName, binaryMessenger: messenger)
        events.setStreamHandler(instance)
        return instance
    }

    private var eventSink: FlutterEventSink?
    private var selfKey = ""
    private var selfAlias = ""
    private var active = false

    private var peerId: MCPeerID?
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    /// MCPeerID.displayName -> (publicKey, alias). Populated from
    /// discoveryInfo (browser side) or invitation context (advertiser
    /// side) — displayName alone carries only a truncated key.
    private var identities: [String: (key: String, alias: String)] = [:]
    private var peersByKey: [String: MCPeerID] = [:]

    // -----------------------------------------------------------------
    // Method channel
    // -----------------------------------------------------------------

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startDiscovery":
            guard let args = call.arguments as? [String: Any],
                let publicKey = args["publicKey"] as? String,
                !publicKey.isEmpty
            else {
                result(FlutterError(
                    code: "BAD_ARGS", message: "publicKey required",
                    details: nil))
                return
            }
            selfKey = publicKey
            selfAlias = (args["alias"] as? String) ?? ""
            startRadios()
            result(nil)

        case "stopDiscovery":
            stopRadios()
            result(nil)

        case "broadcastPayload":
            guard let args = call.arguments as? [String: Any],
                let payload = args["payload"] as? String
            else {
                result(FlutterError(
                    code: "BAD_ARGS", message: "payload required",
                    details: nil))
                return
            }
            guard let session = session, !session.connectedPeers.isEmpty
            else {
                result(FlutterError(
                    code: "NO_PEERS", message: "zero connected peers",
                    details: nil))
                return
            }
            send(payload, to: session.connectedPeers, result: result)

        case "sendPayloadToPeer":
            guard let args = call.arguments as? [String: Any],
                let payload = args["payload"] as? String,
                let key = args["peerPublicKey"] as? String,
                let peer = peersByKey[key],
                let session = session,
                session.connectedPeers.contains(peer)
            else {
                result(FlutterError(
                    code: "PEER_UNREACHABLE", message: "peer not connected",
                    details: nil))
                return
            }
            send(payload, to: [peer], result: result)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func send(
        _ payload: String,
        to peers: [MCPeerID],
        result: @escaping FlutterResult
    ) {
        guard let session = session,
            let data = payload.data(using: .utf8)
        else {
            result(FlutterError(
                code: "RADIO_FAULT", message: "session unavailable",
                details: nil))
            return
        }
        do {
            try session.send(data, toPeers: peers, with: .reliable)
            result(nil)
        } catch {
            result(FlutterError(
                code: "RADIO_FAULT",
                message: error.localizedDescription, details: nil))
        }
    }

    // -----------------------------------------------------------------
    // Event channel
    // -----------------------------------------------------------------

    func onListen(
        withArguments arguments: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }

    private func emit(_ event: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(event)
        }
    }

    private func emitNodeState(_ displayName: String, state: String) {
        guard let identity = identities[displayName] else { return }
        emit([
            "type": "nodeState",
            "node": ["publicKey": identity.key, "alias": identity.alias],
            "state": state,
            "rssi": 0, // Multipeer exposes no RSSI; 0 = n/a.
        ])
    }

    // -----------------------------------------------------------------
    // Radios
    // -----------------------------------------------------------------

    private func startRadios() {
        guard !active else { return }
        active = true

        // displayName caps at 63 UTF-8 bytes — a 64-char hex key plus
        // alias will not fit, so displayName is only a routing handle;
        // real identity travels in discoveryInfo / invitation context.
        let handle = String(selfKey.prefix(16))
        let peer = MCPeerID(displayName: handle)
        peerId = peer

        let session = MCSession(
            peer: peer, securityIdentity: nil,
            encryptionPreference: .required)
        session.delegate = self
        self.session = session

        let advertiser = MCNearbyServiceAdvertiser(
            peer: peer,
            discoveryInfo: ["pk": selfKey, "alias": selfAlias],
            serviceType: Self.serviceType)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser

        let browser = MCNearbyServiceBrowser(
            peer: peer, serviceType: Self.serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser
    }

    private func stopRadios() {
        guard active else { return }
        active = false
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.disconnect()
        advertiser = nil
        browser = nil
        session = nil
        peerId = nil
        identities.removeAll()
        peersByKey.removeAll()
    }

    private func register(
        _ peer: MCPeerID, key: String, alias: String
    ) {
        identities[peer.displayName] = (key: key, alias: alias)
        peersByKey[key] = peer
    }

    private func forget(_ peer: MCPeerID) {
        if let identity = identities.removeValue(forKey: peer.displayName) {
            peersByKey.removeValue(forKey: identity.key)
        }
    }
}

// ---------------------------------------------------------------------
// Browser: found a peer → deterministic initiator invites with identity
// ---------------------------------------------------------------------

extension MultipeerTransportChannel: MCNearbyServiceBrowserDelegate {

    func browser(
        _ browser: MCNearbyServiceBrowser,
        foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String: String]?
    ) {
        guard let key = info?["pk"], !key.isEmpty else { return }
        let alias = info?["alias"] ?? ""
        register(peerID, key: key, alias: alias)
        emitNodeState(peerID.displayName, state: "discovered")

        // Smaller key dials; context carries the inviter's full identity.
        if selfKey < key, let session = session {
            emitNodeState(peerID.displayName, state: "connecting")
            let context = "\(selfKey)|\(selfAlias)".data(using: .utf8)
            browser.invitePeer(
                peerID, to: session, withContext: context, timeout: 15)
        }
    }

    func browser(
        _ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID
    ) {
        emitNodeState(peerID.displayName, state: "lost")
        forget(peerID)
    }
}

// ---------------------------------------------------------------------
// Advertiser: incoming invitation → learn identity from context, accept
// ---------------------------------------------------------------------

extension MultipeerTransportChannel: MCNearbyServiceAdvertiserDelegate {

    func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        // Context format "pk|alias": reject invitations that do not carry
        // a parsable identity — an anonymous radio link is useless to the
        // layers above, which key everything by public key.
        guard let context = context,
            let text = String(data: context, encoding: .utf8),
            let separator = text.firstIndex(of: "|"),
            separator != text.startIndex
        else {
            invitationHandler(false, nil)
            return
        }
        let key = String(text[..<separator])
        let alias = String(text[text.index(after: separator)...])
        register(peerID, key: key, alias: alias)
        emitNodeState(peerID.displayName, state: "connecting")
        // Transport-level accept; trust is per-operation Ed25519 in the
        // CRDT layer, never granted by radio proximity.
        invitationHandler(true, session)
    }
}

// ---------------------------------------------------------------------
// Session: connection state + inbound payloads
// ---------------------------------------------------------------------

extension MultipeerTransportChannel: MCSessionDelegate {

    func session(
        _ session: MCSession, peer peerID: MCPeerID,
        didChange state: MCSessionState
    ) {
        switch state {
        case .connecting:
            emitNodeState(peerID.displayName, state: "connecting")
        case .connected:
            emitNodeState(peerID.displayName, state: "connected")
        case .notConnected:
            emitNodeState(peerID.displayName, state: "lost")
            forget(peerID)
        @unknown default:
            emitNodeState(peerID.displayName, state: "degraded")
        }
    }

    func session(
        _ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID
    ) {
        guard let payload = String(data: data, encoding: .utf8) else { return }
        emit(["type": "payloadReceived", "payload": payload])
    }

    // Unused stream/resource transfer surfaces — required by protocol.
    func session(
        _ session: MCSession, didReceive stream: InputStream,
        withName streamName: String, fromPeer peerID: MCPeerID
    ) {}

    func session(
        _ session: MCSession, didStartReceivingResourceWithName name: String,
        fromPeer peerID: MCPeerID, with progress: Progress
    ) {}

    func session(
        _ session: MCSession, didFinishReceivingResourceWithName name: String,
        fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?
    ) {}
}
