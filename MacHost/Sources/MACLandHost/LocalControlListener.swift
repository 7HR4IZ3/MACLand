import Foundation
import Network
import OSLog
import Security

enum ControlTLSIdentityError: Error, Equatable, Sendable, LocalizedError {
    case notConfigured
    case permissionDenied
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "A production TLS certificate and private key have not been provisioned."
        case .permissionDenied:
            "The host does not have permission to access the configured TLS identity."
        case let .unavailable(reason):
            "The configured TLS identity is unavailable: \(reason)"
        }
    }
}

enum LocalControlListenerError: Error, Equatable, Sendable, LocalizedError {
    case invalidHostName
    case tlsIdentity(ControlTLSIdentityError)

    var errorDescription: String? {
        switch self {
        case .invalidHostName:
            "The host name for LAN control cannot be empty."
        case let .tlsIdentity(error):
            error.localizedDescription
        }
    }
}

enum LocalControlListenerState: Equatable, Sendable {
    case idle
    case ready
    case failed(String)
    case stopped
}

typealias TLSIdentityFactory = () throws -> sec_identity_t

/// A typed Network.framework WebSocket session. Transport readiness is kept
/// separate from pairing, so a TLS connection can never accidentally become an
/// authorized control session merely because its socket opened.
final class ControlWebSocketSession: @unchecked Sendable {
    let id: UUID

    private let queue: DispatchQueue
    private let frameCodec: ControlFrameCodec
    private var connection: NWConnection
    private var stateMachine = ControlTransportStateMachine()
    private let onStateChange: ((ControlTransportState) -> Void)?
    private let onTerminal: (() -> Void)?
    private let onReady: (() -> Void)?
    private let onMessage: ((Data) -> Void)?
    private var nextSequence: UInt64 = 1

    var state: ControlTransportState { stateMachine.state }

    init(
        connection: NWConnection,
        id: UUID = UUID(),
        queue: DispatchQueue,
        frameCodec: ControlFrameCodec = ControlFrameCodec(),
        onStateChange: ((ControlTransportState) -> Void)? = nil,
        onTerminal: (() -> Void)? = nil,
        onReady: (() -> Void)? = nil,
        onMessage: ((Data) -> Void)? = nil
    ) {
        self.connection = connection
        self.id = id
        self.queue = queue
        self.frameCodec = frameCodec
        self.onStateChange = onStateChange
        self.onTerminal = onTerminal
        self.onReady = onReady
        self.onMessage = onMessage
    }

    func start() {
        guard apply(.start) else { return }
        attachAndStart()
    }

    func reconnect(using connection: NWConnection) throws {
        guard case .reconnecting = state else {
            throw ControlTransportError.invalidState
        }
        self.connection = connection
        attachAndStart()
    }

    func prepareForReconnect() throws {
        guard case .established = state else {
            throw ControlTransportError.invalidState
        }
        _ = apply(.transportInterrupted)
    }

    func acceptPairing(sessionID: UUID) throws {
        guard apply(.pairingAccepted(sessionID: sessionID)) else {
            throw ControlTransportError.invalidState
        }
    }

    func rejectPairing() throws {
        guard apply(.pairingRejected) else {
            throw ControlTransportError.invalidState
        }
        close()
    }

    func acceptResume(sessionID: UUID) throws {
        guard apply(.resumeAccepted(sessionID: sessionID)) else {
            throw ControlTransportError.invalidState
        }
    }

    func rejectResume() throws {
        guard apply(.resumeRejected) else {
            throw ControlTransportError.invalidState
        }
    }

    func close() {
        if state != .closed {
            _ = apply(.closeRequested)
            connection.cancel()
            _ = apply(.closed)
        }
        onTerminal?()
    }

    func send<Payload: Codable & Sendable>(
        _ envelope: ControlEnvelope<Payload>,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void = { _ in }
    ) throws {
        guard canSend(kind: envelope.kind) else {
            throw state == .closed ? ControlTransportError.sessionClosed : ControlTransportError.pairingRequired
        }

        let data = try frameCodec.encode(envelope)
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(
            identifier: envelope.id.uuidString,
            metadata: [metadata]
        )
        connection.send(
            content: data,
            contentContext: context,
            isComplete: true,
            completion: .contentProcessed { error in
                if let error {
                    completion(.failure(ControlTransportError.connectionFailed(error.localizedDescription)))
                } else {
                    completion(.success(()))
                }
            }
        )
    }

    func send<Payload: Codable & Sendable>(
        kind: ControlMessageKind,
        payload: Payload,
        requestID: UUID? = nil,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void = { _ in }
    ) throws {
        let envelope = try ControlEnvelope(
            kind: kind,
            sequence: nextSequence,
            requestID: requestID,
            payload: payload
        )
        nextSequence += 1
        try send(envelope, completion: completion)
    }

    func receive<Payload: Codable & Sendable>(
        _ payloadType: Payload.Type = Payload.self,
        expectedKind: ControlMessageKind? = nil,
        completion: @escaping @Sendable (Result<ControlEnvelope<Payload>, Error>) -> Void
    ) {
        connection.receiveMessage { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                completion(.failure(ControlTransportError.connectionFailed(error.localizedDescription)))
                return
            }
            guard isComplete, let data else {
                completion(.failure(ControlFrameError.empty))
                return
            }

            do {
                let envelope = try self.frameCodec.decode(
                    data,
                    as: payloadType,
                    expectedKind: expectedKind
                )
                completion(.success(envelope))
            } catch {
                completion(.failure(error))
            }
        }
    }

    private func attachAndStart() {
        connection.stateUpdateHandler = { [weak self] state in
            self?.handle(connectionState: state)
        }
        connection.start(queue: queue)
    }

    private func handle(connectionState: NWConnection.State) {
        switch connectionState {
        case .ready:
            _ = apply(.transportReady)
            if case .awaitingPairing = state {
                onReady?()
                receiveNextMessage()
            }
        case .waiting(let error):
            if case .established = state {
                _ = apply(.transportInterrupted)
            } else {
                _ = apply(.failed(.connectionFailed(error.localizedDescription)))
            }
        case .failed(let error):
            if case .established = state {
                _ = apply(.transportInterrupted)
            } else {
                _ = apply(.failed(.connectionFailed(error.localizedDescription)))
            }
        case .cancelled:
            if state != .closing && state != .closed {
                _ = apply(.failed(.sessionClosed))
            }
            onTerminal?()
        default:
            break
        }
    }

    private func receiveNextMessage() {
        guard onMessage != nil, state != .closed else { return }
        connection.receiveMessage { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                self.onStateChange?(.failed(.connectionFailed(error.localizedDescription)))
                return
            }
            if isComplete, let data {
                self.onMessage?(data)
            }
            self.receiveNextMessage()
        }
    }

    @discardableResult
    private func apply(_ event: ControlTransportEvent) -> Bool {
        do {
            try stateMachine.apply(event)
            onStateChange?(stateMachine.state)
            return true
        } catch {
            onStateChange?(stateMachine.state)
            return false
        }
    }

    private func canSend(kind: ControlMessageKind) -> Bool {
        switch state {
        case .awaitingPairing:
            [.hostHello, .pairingRequest, .pairingResponse, .error].contains(kind)
        case .resuming:
            [.sessionResume, .error].contains(kind)
        case .established:
            true
        default:
            false
        }
    }
}

final class LocalControlListener: @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.thraize.macland.host", category: "network")
    static let controlPort = NWEndpoint.Port(rawValue: 58943)!

    let hostName: String
    let certificatePinningMetadata: CertificatePinningMetadata?
    let hostID: UUID
    private(set) var pairingCode: String
    private(set) var pairingExpiresAt: Date
    var port: NWEndpoint.Port? { listener?.port }

    private let queue: DispatchQueue
    private let hostHello: HostHelloPayload
    private let pairingApproval: PairingApprovalStore
    private let onSessionStart: ((SessionStartPayload) -> Void)?
    private let onMediaAnswer: ((MediaAnswerPayload) -> Void)?
    private let onMediaICE: ((MediaICEPayload) -> Void)?
    private let onAppLaunch: ((ApplicationCommandPayload) -> Void)?
    private let onAppFocus: ((ApplicationCommandPayload) -> Void)?
    private let onAppClose: ((ApplicationCommandPayload) -> Void)?
    private let onInputBatch: ((InputBatchPayload) -> Void)?
    private let appsListProvider: (() -> AppsListPayload)?
    private var trustedClientIDs = Set<UUID>()
    private var revokedClientIDs = Set<UUID>()
    private var listener: NWListener?
    private var sessions: [UUID: ControlWebSocketSession] = [:]
    private(set) var state: LocalControlListenerState = .idle

    init(
        hostName: String,
        certificatePinningMetadata: CertificatePinningMetadata? = nil,
        tlsIdentityFactory: @escaping TLSIdentityFactory = LocalControlListener.unconfiguredTLSIdentity,
        hostID: UUID = UUID(),
        hostVersion: String = "0.1.0",
        capabilities: Capabilities = Capabilities(),
        permissionState: PermissionState = PermissionState(),
        pairingCode: String = LocalControlListener.makePairingCode(),
        pairingExpiresAt: Date = Date().addingTimeInterval(600),
        pairingApproval: PairingApprovalStore = PairingApprovalStore(),
        onSessionStart: ((SessionStartPayload) -> Void)? = nil,
        onMediaAnswer: ((MediaAnswerPayload) -> Void)? = nil,
        onMediaICE: ((MediaICEPayload) -> Void)? = nil,
        onAppLaunch: ((ApplicationCommandPayload) -> Void)? = nil,
        onAppFocus: ((ApplicationCommandPayload) -> Void)? = nil,
        onAppClose: ((ApplicationCommandPayload) -> Void)? = nil,
        onInputBatch: ((InputBatchPayload) -> Void)? = nil,
        appsListProvider: (() -> AppsListPayload)? = nil
    ) throws {
        guard !hostName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LocalControlListenerError.invalidHostName
        }

        self.hostName = hostName
        self.certificatePinningMetadata = certificatePinningMetadata
        self.hostID = hostID
        self.pairingCode = pairingCode
        self.pairingExpiresAt = pairingExpiresAt
        self.pairingApproval = pairingApproval
        self.onSessionStart = onSessionStart
        self.onMediaAnswer = onMediaAnswer
        self.onMediaICE = onMediaICE
        self.onAppLaunch = onAppLaunch
        self.onAppFocus = onAppFocus
        self.onAppClose = onAppClose
        self.onInputBatch = onInputBatch
        self.appsListProvider = appsListProvider
        self.queue = DispatchQueue(label: "com.thraize.macland.control", qos: .userInitiated)
        self.hostHello = HostHelloPayload(
            hostID: hostID,
            hostName: hostName,
            hostVersion: hostVersion,
            capabilities: capabilities,
            permissionState: permissionState,
            hostIdentity: DeviceIdentityMetadata(
                deviceID: hostID,
                deviceName: hostName,
                platform: .macOS,
                appVersion: hostVersion,
                publicKeySHA256: certificatePinningMetadata?.publicKeySHA256
            ),
            certificatePinning: certificatePinningMetadata
        )

        let identity: sec_identity_t
        do {
            identity = try tlsIdentityFactory()
        } catch let error as ControlTLSIdentityError {
            throw LocalControlListenerError.tlsIdentity(error)
        } catch {
            throw LocalControlListenerError.tlsIdentity(.unavailable(error.localizedDescription))
        }

        let tlsOptions = NWProtocolTLS.Options()
        sec_protocol_options_set_local_identity(tlsOptions.securityProtocolOptions, identity)

        let parameters = NWParameters(tls: tlsOptions, tcp: NWProtocolTCP.Options())
        parameters.defaultProtocolStack.applicationProtocols.insert(NWProtocolWebSocket.Options(), at: 0)

        let listener = try NWListener(using: parameters, on: Self.controlPort)
        listener.service = NWListener.Service(
            name: hostName,
            type: "_macland._tcp",
            domain: nil,
            txtRecord: nil
        )
        self.listener = listener
    }

    func start() {
        guard let listener else { return }
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.state = .ready
                Self.logger.info("Secure LAN control listener is ready")
            case let .failed(error):
                self.state = .failed(error.localizedDescription)
                Self.logger.error("LAN listener failed: \(error.localizedDescription, privacy: .public)")
            case .cancelled:
                self.state = .stopped
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
    }

    func stop() {
        sessions.values.forEach { $0.close() }
        sessions.removeAll()
        listener?.cancel()
        listener = nil
        state = .stopped
    }

    func setPairingApprovalEnabled(_ enabled: Bool) {
        pairingApproval.setEnabled(enabled)
    }

    func rotatePairingCode() {
        queue.sync {
            pairingCode = Self.makePairingCode()
            pairingExpiresAt = Date().addingTimeInterval(600)
        }
    }

    func revoke(clientID: UUID) {
        trustedClientIDs.remove(clientID)
        revokedClientIDs.insert(clientID)
    }

    func isTrusted(clientID: UUID) -> Bool {
        trustedClientIDs.contains(clientID) && !revokedClientIDs.contains(clientID)
    }

    func sendToPairedClients<Payload: Codable & Sendable>(
        kind: ControlMessageKind,
        payload: Payload,
        requestID: UUID? = nil
    ) {
        for session in sessions.values {
            guard case .established = session.state else { continue }
            try? session.send(kind: kind, payload: payload, requestID: requestID)
        }
    }

    private func accept(_ connection: NWConnection) {
        let sessionID = UUID()
        let sessionBox = WeakControlWebSocketSessionBox()
        let session = ControlWebSocketSession(
            connection: connection,
            id: sessionID,
            queue: queue,
            onStateChange: { state in
                Self.logger.debug("Control session \(sessionID.uuidString, privacy: .public) state: \(String(describing: state), privacy: .public)")
            },
            onTerminal: { [weak self] in
                self?.sessions.removeValue(forKey: sessionID)
            },
            onReady: { [weak self] in
                guard let self, let session = sessionBox.session else { return }
                do {
                    try session.send(kind: .hostHello, payload: self.hostHello)
                } catch {
                    Self.logger.error("Could not send host hello: \(error.localizedDescription, privacy: .public)")
                    session.close()
                }
            },
            onMessage: { [weak self] data in
                guard let self, let session = sessionBox.session else { return }
                self.handle(data: data, session: session)
            }
        )
        sessionBox.session = session
        sessions[sessionID] = session
        session.start()
    }

    private func handle(data: Data, session: ControlWebSocketSession) {
        do {
            let header = try MACLandJSON.makeDecoder().decode(ControlMessageHeader.self, from: data)
            switch header.kind {
            case .pairingRequest:
                try handlePairing(data: data, session: session)
            case .sessionResume:
                try sendError(
                    code: .sessionExpired,
                    message: "Session resume requires a previously paired device and is not available on this new transport.",
                    retryable: true,
                    session: session,
                    requestID: header.id
                )
            case .heartbeat:
                try handleHeartbeat(data: data, session: session)
            case .sessionStart:
                try handleSessionStart(data: data, session: session)
            case .mediaAnswer:
                try handleMediaAnswer(data: data, session: session)
            case .mediaICE:
                try handleMediaICE(data: data, session: session)
            case .appsList:
                try handleAppsList(session: session)
            case .appLaunch:
                try handleApplicationCommand(data: data, expectedKind: .appLaunch, session: session, callback: onAppLaunch)
            case .appFocus:
                try handleApplicationCommand(data: data, expectedKind: .appFocus, session: session, callback: onAppFocus)
            case .appClose:
                try handleApplicationCommand(data: data, expectedKind: .appClose, session: session, callback: onAppClose)
            case .inputBatch:
                try handleInputBatch(data: data, session: session)
            default:
                try sendError(
                    code: .unavailable,
                    message: "The host has no typed handler for \(header.kind.rawValue) yet.",
                    retryable: false,
                    session: session,
                    requestID: header.id
                )
            }
        } catch {
            try? sendError(
                code: .malformedMessage,
                message: error.localizedDescription,
                retryable: false,
                session: session,
                requestID: nil
            )
        }
    }

    private func handlePairing(data: Data, session: ControlWebSocketSession) throws {
        let envelope = try ControlEnvelope<PairingRequestPayload>.decode(
            from: data,
            expectedKind: .pairingRequest
        )
        let request = envelope.payload
        guard request.pairingCode == pairingCode, Date() < pairingExpiresAt else {
            try rejectPairing(request: request, reason: "The pairing code is invalid or expired.", session: session, requestID: envelope.id)
            return
        }
        guard !revokedClientIDs.contains(request.clientID), pairingApproval.isEnabled else {
            try rejectPairing(request: request, reason: "Host confirmation is required before pairing.", session: session, requestID: envelope.id)
            return
        }

        let sessionID = UUID()
        trustedClientIDs.insert(request.clientID)
        try session.send(
            kind: .pairingResponse,
            payload: PairingResponsePayload(
                accepted: true,
                clientID: request.clientID,
                hostID: hostID,
                hostIdentity: hostHello.hostIdentity,
                certificatePinning: certificatePinningMetadata
            ),
            requestID: envelope.id
        )
        try session.acceptPairing(sessionID: sessionID)
    }

    private func rejectPairing(
        request: PairingRequestPayload,
        reason: String,
        session: ControlWebSocketSession,
        requestID: UUID
    ) throws {
        try session.send(
            kind: .pairingResponse,
            payload: PairingResponsePayload(
                accepted: false,
                clientID: request.clientID,
                hostID: hostID,
                reason: reason,
                hostIdentity: hostHello.hostIdentity,
                certificatePinning: certificatePinningMetadata
            ),
            requestID: requestID
        )
        try session.rejectPairing()
    }

    private func handleHeartbeat(data: Data, session: ControlWebSocketSession) throws {
        let envelope = try ControlEnvelope<HeartbeatPayload>.decode(from: data, expectedKind: .heartbeat)
        guard case .established = session.state else { throw ControlTransportError.pairingRequired }
        guard envelope.payload.kind == .ping else { return }
        try session.send(
            kind: .heartbeat,
            payload: HeartbeatPayload(
                kind: .pong,
                heartbeatID: envelope.payload.heartbeatID,
                sentAt: envelope.payload.sentAt,
                acknowledgedSequence: envelope.sequence
            ),
            requestID: envelope.id
        )
    }

    private func handleSessionStart(data: Data, session: ControlWebSocketSession) throws {
        let envelope = try ControlEnvelope<SessionStartPayload>.decode(from: data, expectedKind: .sessionStart)
        guard case .established = session.state else { throw ControlTransportError.pairingRequired }
        onSessionStart?(envelope.payload)
        try session.send(
            kind: .sessionState,
            payload: SessionStatePayload(
                sessionID: envelope.payload.sessionID,
                state: .negotiating,
                displayID: envelope.payload.displayID
            ),
            requestID: envelope.id
        )
        if let appsList = appsListProvider?() {
            try session.send(kind: .appsList, payload: appsList, requestID: envelope.id)
        }
    }

    private func handleMediaAnswer(data: Data, session: ControlWebSocketSession) throws {
        let envelope = try ControlEnvelope<MediaAnswerPayload>.decode(from: data, expectedKind: .mediaAnswer)
        guard case .established = session.state else { throw ControlTransportError.pairingRequired }
        onMediaAnswer?(envelope.payload)
        Self.logger.debug("Received WebRTC answer for \(envelope.payload.sessionID.uuidString, privacy: .public)")
    }

    private func handleMediaICE(data: Data, session: ControlWebSocketSession) throws {
        let envelope = try ControlEnvelope<MediaICEPayload>.decode(from: data, expectedKind: .mediaICE)
        guard case .established = session.state else { throw ControlTransportError.pairingRequired }
        onMediaICE?(envelope.payload)
    }

    private func handleAppsList(session: ControlWebSocketSession) throws {
        guard case .established = session.state else { throw ControlTransportError.pairingRequired }
        if let appsList = appsListProvider?() {
            try session.send(kind: .appsList, payload: appsList)
        }
    }

    private func handleApplicationCommand(
        data: Data,
        expectedKind: ControlMessageKind,
        session: ControlWebSocketSession,
        callback: ((ApplicationCommandPayload) -> Void)?
    ) throws {
        let envelope = try ControlEnvelope<ApplicationCommandPayload>.decode(
            from: data,
            expectedKind: expectedKind
        )
        guard case .established = session.state else { throw ControlTransportError.pairingRequired }
        callback?(envelope.payload)
    }

    private func handleInputBatch(data: Data, session: ControlWebSocketSession) throws {
        let envelope = try ControlEnvelope<InputBatchPayload>.decode(from: data, expectedKind: .inputBatch)
        guard case .established = session.state else { throw ControlTransportError.pairingRequired }
        onInputBatch?(envelope.payload)
    }

    private func sendError(
        code: ControlErrorCode,
        message: String,
        retryable: Bool,
        session: ControlWebSocketSession,
        requestID: UUID?
    ) throws {
        try session.send(
            kind: .error,
            payload: ErrorPayload(code: code, message: message, retryable: retryable),
            requestID: requestID
        )
    }

    private static func unconfiguredTLSIdentity() throws -> sec_identity_t {
        throw ControlTLSIdentityError.notConfigured
    }

    private static func makePairingCode() -> String {
        String(format: "%06d", Int.random(in: 0...999_999))
    }
}

private struct ControlMessageHeader: Decodable {
    let kind: ControlMessageKind
    let id: UUID
}

final class PairingApprovalStore: @unchecked Sendable {
    private let lock = NSLock()
    private var enabled: Bool

    init(enabled: Bool = false) {
        self.enabled = enabled
    }

    var isEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return enabled
    }

    func setEnabled(_ enabled: Bool) {
        lock.lock()
        self.enabled = enabled
        lock.unlock()
    }
}

private final class WeakControlWebSocketSessionBox: @unchecked Sendable {
    weak var session: ControlWebSocketSession?
}
