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
    public let hostID: UUID?
    public let certificateSHA256: String?

    public init(id: String, name: String, endpointDescription: String, hostID: UUID? = nil, certificateSHA256: String? = nil) {
        self.id = id; self.name = name; self.endpointDescription = endpointDescription
        self.hostID = hostID; self.certificateSHA256 = certificateSHA256
    }

    public func pairingPayload(code: String) throws -> PairingQRCodePayload {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 6, trimmed.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else {
            throw MACLandControlClientError.invalidPairingCode
        }
        guard let hostID, let pin = certificateSHA256, pin.count == 64,
              pin.allSatisfy({ $0.isHexDigit }), endpointDescription.hasPrefix("wss://") else {
            throw MACLandControlClientError.hostNotReady
        }
        return PairingQRCodePayload(hostIdentity: DeviceIdentityMetadata(deviceID: hostID, deviceName: name, platform: .macOS, appVersion: "0.1.0"),
            endpoint: endpointDescription, pairingCode: trimmed, certificatePinning: CertificatePinningMetadata(certificateSHA256: pin),
            expiresAt: Date().addingTimeInterval(600), nonce: UUID().uuidString)
    }
}

@MainActor
public final class MACLandBonjourDiscovery: NSObject, ObservableObject, @preconcurrency NetServiceBrowserDelegate, @preconcurrency NetServiceDelegate {
    @Published public private(set) var hosts: [MACLandDiscoveredHost] = []
    @Published public private(set) var lastError: String?
    private var browser: NetServiceBrowser?
    private var services: [String: NetService] = [:]
    public override init() { super.init() }

    public func start() {
        stop(); lastError = nil
        let browser = NetServiceBrowser(); browser.delegate = self
        self.browser = browser
        browser.searchForServices(ofType: "_macland._tcp.", inDomain: "local.")
    }
    public func stop() {
        browser?.stop(); browser?.delegate = nil; browser = nil
        for service in services.values { service.stopMonitoring(); service.stop(); service.delegate = nil }
        services.removeAll(); hosts = []
    }
    public func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        services[service.name] = service; service.delegate = self; service.startMonitoring(); service.resolve(withTimeout: 8)
    }
    public func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        services.removeValue(forKey: service.name)?.stopMonitoring(); service.stop(); hosts.removeAll { $0.id == service.name }
    }
    public func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        lastError = "Mac discovery is unavailable. Allow Local Network access for MACLand in iPhone Settings and check that both devices use the same Wi-Fi."
    }
    public func netServiceDidResolveAddress(_ sender: NetService) {
        guard services[sender.name] === sender, let hostname = sender.hostName, sender.port > 0 else { return }
        let record = sender.txtRecordData().map(NetService.dictionary(fromTXTRecord:)) ?? [:]
        var url = URLComponents(); url.scheme = "wss"; url.host = hostname; url.port = sender.port
        guard let endpoint = url.url?.absoluteString else { return }
        let host = MACLandDiscoveredHost(id: sender.name, name: sender.name, endpointDescription: endpoint,
            hostID: record["host-id"].flatMap { String(data: $0, encoding: .utf8) }.flatMap(UUID.init(uuidString:)),
            certificateSHA256: record["cert-sha256"].flatMap { String(data: $0, encoding: .utf8) })
        hosts.removeAll { $0.id == host.id }; hosts.append(host); hosts.sort { $0.name < $1.name }
    }
    public func netService(_ sender: NetService, didUpdateTXTRecord data: Data) {
        netServiceDidResolveAddress(sender)
    }
    public func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        lastError = "Could not find the Mac's network address. Check Wi-Fi and scan again."
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

    public var onInputError: ((String) -> Void)?
    public var onStateChange: ((MACLandControlClientState) -> Void)?
    public var onDisplayState: ((DisplayStatePayload) -> Void)?
    public var onSessionState: ((SessionStatePayload) -> Void)?

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var receiveTask: Task<Void, Never>?
    private var connectionTimeoutTask: Task<Void, Never>?
    private var pairingPayload: PairingQRCodePayload?
    private var pendingDiscoveredHostID: String?
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

    public func connect(to host: MACLandDiscoveredHost, code: String) throws {
        let payload = try host.pairingPayload(code: code)
        let key = "macland.trusted-host-pin." + host.id
        if let known = UserDefaults.standard.string(forKey: key), known != host.certificateSHA256 {
            throw MACLandControlClientError.certificateChanged
        }
        try connect(using: payload)
        pendingDiscoveredHostID = host.id
    }

    public func connect(using pairingPayload: PairingQRCodePayload) throws {
        guard let url = Self.webSocketURL(from: pairingPayload.endpoint) else {
            throw MACLandControlClientError.invalidEndpoint(pairingPayload.endpoint)
        }

        disconnect(clearPairing: false)
        pendingDiscoveredHostID = pairingPayload.hostIdentity.deviceName
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
                let shouldReconnect = state == .connected || state == .reconnecting
                fail(connectionFailureMessage(error))
                if shouldReconnect && certificatePinStore.validationFailure == nil { reconnect() }
            }
        }
    }

    func handle(data: Data) {
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
                if let host = pendingDiscoveredHostID, let pin = pairingPayload?.certificatePinning.certificateSHA256 {
                    UserDefaults.standard.set(pin, forKey: "macland.trusted-host-pin." + host)
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
                if envelope.payload.details?["capability"] == "input" {
                    onInputError?(envelope.payload.message)
                } else {
                    fail(envelope.payload.message)
                }
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
                guard let self, webSocketTask === self.webSocketTask else { return }
                self.fail(self.connectionFailureMessage(error))
            }
        }
    }

    private func connectionFailureMessage(_ error: Error) -> String {
        if let validationFailure = certificatePinStore.validationFailure { return validationFailure }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return "The secure connection was cancelled. Scan for your Mac again, check its current code, and retry."
        }
        return error.localizedDescription
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
    case invalidPairingCode
    case hostNotReady
    case certificateChanged
    case invalidEndpoint(String)
    case notConnected

    public var errorDescription: String? {
        switch self {
        case .invalidPairingCode: "Enter the six-digit pairing code shown on your Mac."
        case .hostNotReady: "Restart the updated MACLand host, then scan again."
        case .certificateChanged: "This Mac's security certificate has changed. Use pairing data from the Mac to verify it again."
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
                guard let self, webSocketTask === self.webSocketTask else { return }
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
            guard let self, webSocketTask === self.webSocketTask, state != .idle, state != .failed else { return }
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
            guard state != .idle, state != .failed else { return }
            fail(error.map(connectionFailureMessage) ?? "The secure connection to the Mac host closed before pairing completed.")
        }
    }
}

extension MACLandControlClient: URLSessionDelegate {
    nonisolated public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        guard let trust = challenge.protectionSpace.serverTrust,
              let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let certificate = chain.first,
              let expected = self.certificatePinStore.value else {
            self.certificatePinStore.recordFailure("The Mac did not provide a verifiable certificate. Scan for the updated host again.")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let digest = SHA256.hash(data: SecCertificateCopyData(certificate) as Data)
        let actual = digest.map { String(format: "%02x", $0) }.joined()
        guard actual == expected else {
            self.certificatePinStore.recordFailure("The Mac's certificate does not match its pairing details. Scan again instead of using old pairing data.")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}

private final class CertificatePinStore: @unchecked Sendable {
    private let lock = NSLock()
    private var pin: String?
    private var failure: String?

    var validationFailure: String? {
        lock.lock(); defer { lock.unlock() }; return failure
    }
    func recordFailure(_ message: String) {
        lock.lock(); defer { lock.unlock() }; failure = message
    }

    var value: String? {
        lock.lock()
        defer { lock.unlock() }
        return pin
    }

    func set(_ pin: String?) {
        lock.lock()
        self.pin = pin
        self.failure = nil
        lock.unlock()
    }
}
