import CryptoKit
import Foundation
import Network
import Security

public enum MACLandControlClientState: String, Sendable {
    case idle
    case connecting
    case pairing
    case connected
    case reconnecting
    case failed

    public var label: String {
        switch self {
        case .idle: "Control idle"
        case .connecting: "Connecting to host"
        case .pairing: "Waiting for host pairing"
        case .connected: "Control connected"
        case .reconnecting: "Reconnecting to host"
        case .failed: "Control unavailable"
        }
    }
}

public struct MACLandDiscoveredHost: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let endpointDescription: String

    public init(id: String, name: String, endpointDescription: String) {
        self.id = id
        self.name = name
        self.endpointDescription = endpointDescription
    }
}

/// Bonjour discovery is intentionally separate from the WebSocket client. A
/// QR payload carries the authoritative hostname, port, and pin; Bonjour only
/// helps the phone show nearby MACLand hosts before pairing.
@MainActor
public final class MACLandBonjourDiscovery: ObservableObject {
    @Published public private(set) var hosts: [MACLandDiscoveredHost] = []

    private var browser: NWBrowser?

    public init() {}

    public func start() {
        stop()
        let browser = NWBrowser(
            for: .bonjour(type: "_macland._tcp", domain: nil),
            using: NWParameters.tcp
        )
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let hosts = results.map { result in
                MACLandDiscoveredHost(
                    id: result.endpoint.debugDescription,
                    name: result.endpoint.debugDescription,
                    endpointDescription: result.endpoint.debugDescription
                )
            }
            Task { @MainActor [weak self] in
                self?.hosts = hosts.sorted { $0.name < $1.name }
            }
        }
        browser.stateUpdateHandler = { _ in }
        browser.start(queue: .main)
        self.browser = browser
    }

    public func stop() {
        browser?.cancel()
        browser = nil
        hosts = []
    }
}

@MainActor
public final class MACLandControlClient: NSObject, ObservableObject {
    @Published public private(set) var state: MACLandControlClientState = .idle
    @Published public private(set) var applications: [ApplicationDescriptor] = []
    @Published public private(set) var hostName = ""
    @Published public private(set) var pairingCode = ""
    @Published public private(set) var lastError: String?

    public let clientID: UUID
    public let clientName: String
    public let webRTCClient: NativeWebRTCClient

    public var onStateChange: ((MACLandControlClientState) -> Void)?
    public var onDisplayState: ((DisplayStatePayload) -> Void)?
    public var onSessionState: ((SessionStatePayload) -> Void)?

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var receiveTask: Task<Void, Never>?
    private var connectionTimeoutTask: Task<Void, Never>?
    private var pairingPayload: PairingQRCodePayload?
    private var currentSessionID: UUID?
    private var nextSequence: UInt64 = 1
    private var reconnectTask: Task<Void, Never>?
    private let certificatePinStore = CertificatePinStore()

    public init(
        clientName: String = "iPhone",
        webRTCClient: NativeWebRTCClient = NativeWebRTCClient()
    ) {
        let storedID = UserDefaults.standard.string(forKey: "macland.client.id")
            .flatMap(UUID.init(uuidString:))
        let resolvedID = storedID ?? UUID()
        if storedID == nil {
            UserDefaults.standard.set(resolvedID.uuidString, forKey: "macland.client.id")
        }
        self.clientID = resolvedID
        self.clientName = clientName
        self.webRTCClient = webRTCClient
        super.init()
        configureWebRTCICEForwarding()
    }

    public func connect(using pairingPayload: PairingQRCodePayload) throws {
        guard let url = Self.webSocketURL(from: pairingPayload.endpoint) else {
            throw MACLandControlClientError.invalidEndpoint(pairingPayload.endpoint)
        }

        disconnect(clearPairing: false)
        self.pairingPayload = pairingPayload
        pairingCode = pairingPayload.pairingCode
        certificatePinStore.set(pairingPayload.certificatePinning.certificateSHA256.lowercased())
        setState(.connecting)
        lastError = nil

        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        let task = session.webSocketTask(with: url)
        self.urlSession = session
        self.webSocketTask = task
        task.resume()

        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled, let self, self.state == .connecting else { return }
            self.fail("The Mac host did not respond within 12 seconds. Check that MACLand Host is running and both devices are on the same Wi‑Fi network.")
            self.webSocketTask?.cancel()
        }
    }

    public func disconnect(clearPairing: Bool = true) {
        applications = []
        receiveTask?.cancel()
        receiveTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        currentSessionID = nil
        webRTCClient.stop()
        if clearPairing {
            pairingPayload = nil
            pairingCode = ""
        }
        setState(.idle)
    }

    public func reconnect() {
        guard let pairingPayload else { return }
        reconnectTask?.cancel()
        reconnectTask = Task { @MainActor [weak self] in
            self?.setState(.reconnecting)
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            try? self?.connect(using: pairingPayload)
        }
    }

    public func requestApplications() throws {
        try send(kind: .appsList, payload: AppsListPayload(applications: []))
    }

    public func sendInput(events: [InputEvent]) throws {
        guard !events.isEmpty else { return }
        try send(
            kind: .inputBatch,
            payload: InputBatchPayload(batchID: UUID(), events: events)
        )
    }

    public func launchApplication(bundleIdentifier: String) throws {
        try send(
            kind: .appLaunch,
            payload: ApplicationCommandPayload(bundleIdentifier: bundleIdentifier)
        )
    }

    public func focusApplication(bundleIdentifier: String) throws {
        try send(
            kind: .appFocus,
            payload: ApplicationCommandPayload(bundleIdentifier: bundleIdentifier)
        )
    }

    public func closeApplication(bundleIdentifier: String) throws {
        try send(
            kind: .appClose,
            payload: ApplicationCommandPayload(bundleIdentifier: bundleIdentifier)
        )
    }

    private func sendPairingRequest() {
        guard let pairingPayload else { return }
        let identity = DeviceIdentityMetadata(
            deviceID: clientID,
            deviceName: clientName,
            platform: .iOS,
            appVersion: "0.1.0"
        )
        do {
            try send(
                kind: .pairingRequest,
                payload: PairingRequestPayload(
                    clientID: clientID,
                    clientName: clientName,
                    pairingCode: pairingPayload.pairingCode,
                    clientIdentity: identity
                )
            )
            setState(.pairing)
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func beginSession(hostID: UUID) {
        let sessionID = UUID()
        currentSessionID = sessionID
        do {
            try send(
                kind: .sessionStart,
                payload: SessionStartPayload(
                    sessionID: sessionID,
                    clientID: clientID,
                    displayID: UUID()
                )
            )
            setState(.connected)
            _ = hostID
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func receiveLoop(for task: URLSessionWebSocketTask) {
        receiveTask?.cancel()
        receiveTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                while !Task.isCancelled {
                    let message = try await task.receive()
                    switch message {
                    case let .data(data):
                        handle(data: data)
                    case let .string(string):
                        handle(data: Data(string.utf8))
                    @unknown default:
                        break
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                fail(error.localizedDescription)
                reconnect()
            }
        }
    }

    private func handle(data: Data) {
        do {
            let header = try MACLandJSON.makeDecoder().decode(ControlMessageHeader.self, from: data)
            switch header.kind {
            case .hostHello:
                let envelope = try ControlEnvelope<HostHelloPayload>.decode(from: data, expectedKind: .hostHello)
                hostName = envelope.payload.hostName
            case .pairingResponse:
                let envelope = try ControlEnvelope<PairingResponsePayload>.decode(from: data, expectedKind: .pairingResponse)
                guard envelope.payload.accepted else {
                    fail(envelope.payload.reason ?? "The host rejected pairing.")
                    return
                }
                beginSession(hostID: envelope.payload.hostID)
            case .sessionState:
                let envelope = try ControlEnvelope<SessionStatePayload>.decode(from: data, expectedKind: .sessionState)
                onSessionState?(envelope.payload)
            case .displayState:
                let envelope = try ControlEnvelope<DisplayStatePayload>.decode(from: data, expectedKind: .displayState)
                onDisplayState?(envelope.payload)
            case .appsList:
                let envelope = try ControlEnvelope<AppsListPayload>.decode(from: data, expectedKind: .appsList)
                applications = envelope.payload.applications.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            case .mediaOffer:
                let envelope = try ControlEnvelope<MediaOfferPayload>.decode(from: data, expectedKind: .mediaOffer)
                handleMediaOffer(envelope)
            case .mediaICE:
                let envelope = try ControlEnvelope<MediaICEPayload>.decode(from: data, expectedKind: .mediaICE)
                handleMediaICE(envelope.payload)
            case .heartbeat:
                let envelope = try ControlEnvelope<HeartbeatPayload>.decode(from: data, expectedKind: .heartbeat)
                if envelope.payload.kind == .pong { return }
            case .error:
                let envelope = try ControlEnvelope<ErrorPayload>.decode(from: data, expectedKind: .error)
                fail(envelope.payload.message)
            default:
                break
            }
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func handleMediaOffer(_ envelope: ControlEnvelope<MediaOfferPayload>) {
        currentSessionID = envelope.payload.sessionID
#if canImport(WebRTC) && !SWIFT_PACKAGE
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let answer = try await webRTCClient.applyRemoteOffer(sdp: envelope.payload.sdp)
                try send(
                    kind: .mediaAnswer,
                    payload: MediaAnswerPayload(
                        sessionID: envelope.payload.sessionID,
                        sdp: answer,
                        width: envelope.payload.width,
                        height: envelope.payload.height,
                        frameRate: envelope.payload.frameRate
                    )
                )
            } catch {
                fail(error.localizedDescription)
            }
        }
#else
        fail("Native WebRTC is only available in the iOS application target.")
#endif
    }

    private func handleMediaICE(_ payload: MediaICEPayload) {
#if canImport(WebRTC) && !SWIFT_PACKAGE
        guard let mLineIndex = payload.sdpMLineIndex else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await webRTCClient.addRemoteICECandidate(
                sdp: payload.candidate,
                sdpMLineIndex: mLineIndex,
                sdpMid: payload.sdpMid
            )
        }
#else
        _ = payload
#endif
    }

    private func configureWebRTCICEForwarding() {
#if canImport(WebRTC) && !SWIFT_PACKAGE
        webRTCClient.onLocalICECandidate = { [weak self] candidate in
            Task { @MainActor [weak self] in
                guard let self, let sessionID = self.currentSessionID else { return }
                try? self.send(
                    kind: .mediaICE,
                    payload: MediaICEPayload(
                        sessionID: sessionID,
                        candidate: candidate.sdp,
                        sdpMid: candidate.sdpMid,
                        sdpMLineIndex: candidate.sdpMLineIndex
                    )
                )
            }
        }
#endif
    }

    private func send<Payload: Codable & Sendable>(
        kind: ControlMessageKind,
        payload: Payload,
        requestID: UUID? = nil
    ) throws {
        guard let webSocketTask else {
            throw MACLandControlClientError.notConnected
        }
        let envelope = try ControlEnvelope(
            kind: kind,
            sequence: nextSequence,
            requestID: requestID,
            payload: payload
        )
        nextSequence += 1
        let data = try ControlFrameCodec().encode(envelope)
        webSocketTask.send(.data(data)) { [weak self] error in
            guard let error else { return }
            Task { @MainActor [weak self] in
                self?.fail(error.localizedDescription)
            }
        }
    }

    private func fail(_ message: String) {
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        lastError = message
        setState(.failed)
    }

    private func setState(_ newState: MACLandControlClientState) {
        state = newState
        onStateChange?(newState)
    }

    private static func webSocketURL(from endpoint: String) -> URL? {
        if let url = URL(string: endpoint), url.scheme == "wss" || url.scheme == "ws" {
            return url
        }
        return URL(string: "wss://" + endpoint)
    }
}

public enum MACLandControlClientError: LocalizedError, Equatable {
    case invalidEndpoint(String)
    case notConnected

    public var errorDescription: String? {
        switch self {
        case let .invalidEndpoint(endpoint): "The pairing endpoint is invalid: " + endpoint
        case .notConnected: "The secure MACLand control channel is not connected."
        }
    }
}

private struct ControlMessageHeader: Decodable {
    let kind: ControlMessageKind
    let id: UUID
}

extension MACLandControlClient: URLSessionWebSocketDelegate {
        nonisolated public func urlSession(
            _ session: URLSession,
            webSocketTask: URLSessionWebSocketTask,
            didOpenWithProtocol protocol: String?
        ) {
            Task { @MainActor [weak self] in
                guard let self else { return }
                connectionTimeoutTask?.cancel()
                connectionTimeoutTask = nil
                setState(.pairing)
                receiveLoop(for: webSocketTask)
                sendPairingRequest()
        }
    }

    nonisolated public func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
        ) {
            Task { @MainActor [weak self] in
            guard let self, webSocketTask === self.webSocketTask else { return }
            setState(.reconnecting)
            reconnect()
        }
    }
}

extension MACLandControlClient: URLSessionTaskDelegate {
    nonisolated public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        Task { @MainActor [weak self] in
            guard let self, task === self.webSocketTask else { return }
            guard state != .idle else { return }
            fail(error?.localizedDescription ?? "The secure connection to the Mac host closed before pairing completed.")
        }
    }
}

extension MACLandControlClient: URLSessionDelegate {
    nonisolated public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              let certificate = SecTrustGetCertificateAtIndex(trust, 0),
              let expected = self.certificatePinStore.value else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let digest = SHA256.hash(data: SecCertificateCopyData(certificate) as Data)
        let actual = digest.map { String(format: "%02x", $0) }.joined()
        guard actual == expected else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}

private final class CertificatePinStore: @unchecked Sendable {
    private let lock = NSLock()
    private var pin: String?

    var value: String? {
        lock.lock()
        defer { lock.unlock() }
        return pin
    }

    func set(_ pin: String?) {
        lock.lock()
        self.pin = pin
        lock.unlock()
    }
}
