import Foundation

public enum Capability: String, Codable, CaseIterable, Sendable {
    case displayEnumeration = "display.enumeration"
    case screenCapture = "screen.capture"
    case inputInjection = "input.injection"
    case clipboardRead = "clipboard.read"
    case clipboardWrite = "clipboard.write"
    case audioCapture = "audio.capture"
    case videoCapture = "video.capture"
}

public struct Capabilities: Codable, Equatable, Sendable {
    public var values: [Capability]

    public init(values: [Capability] = []) {
        self.values = values
    }

    public func contains(_ capability: Capability) -> Bool { values.contains(capability) }
}

public enum PermissionStatus: String, Codable, CaseIterable, Sendable {
    case unknown
    case notDetermined = "not_determined"
    case denied
    case granted
    case restricted
}

public struct PermissionState: Codable, Equatable, Sendable {
    public var screenRecording: PermissionStatus
    public var accessibility: PermissionStatus
    public var inputMonitoring: PermissionStatus
    public var notifications: PermissionStatus

    public init(
        screenRecording: PermissionStatus = .unknown,
        accessibility: PermissionStatus = .unknown,
        inputMonitoring: PermissionStatus = .unknown,
        notifications: PermissionStatus = .unknown
    ) {
        self.screenRecording = screenRecording
        self.accessibility = accessibility
        self.inputMonitoring = inputMonitoring
        self.notifications = notifications
    }
}

public enum DevicePlatform: String, Codable, CaseIterable, Sendable {
    case macOS = "macos"
    case iOS = "ios"
    case unknown
}

/// Stable, non-secret device metadata used during pairing and session setup.
public struct DeviceIdentityMetadata: Codable, Equatable, Sendable {
    public var deviceID: UUID
    public var deviceName: String
    public var platform: DevicePlatform
    public var appVersion: String
    public var publicKeySHA256: String?

    public init(
        deviceID: UUID,
        deviceName: String,
        platform: DevicePlatform,
        appVersion: String,
        publicKeySHA256: String? = nil
    ) {
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.platform = platform
        self.appVersion = appVersion
        self.publicKeySHA256 = publicKeySHA256
    }
}

public enum CertificateDigestAlgorithm: String, Codable, CaseIterable, Sendable {
    case sha256
}

/// Metadata is advertised in pairing data; it is not a substitute for TLS
/// trust evaluation or a provisioned identity.
public struct CertificatePinningMetadata: Codable, Equatable, Sendable {
    public var algorithm: CertificateDigestAlgorithm
    public var certificateSHA256: String
    public var publicKeySHA256: String?

    public init(
        algorithm: CertificateDigestAlgorithm = .sha256,
        certificateSHA256: String,
        publicKeySHA256: String? = nil
    ) {
        self.algorithm = algorithm
        self.certificateSHA256 = certificateSHA256
        self.publicKeySHA256 = publicKeySHA256
    }
}

public struct PairingQRCodePayload: Codable, Equatable, Sendable {
    public var schema: String
    public var protocolVersion: ProtocolVersion
    public var hostIdentity: DeviceIdentityMetadata
    public var endpoint: String
    public var pairingCode: String
    public var certificatePinning: CertificatePinningMetadata
    public var expiresAt: Date
    public var nonce: String

    public init(
        protocolVersion: ProtocolVersion = .current,
        hostIdentity: DeviceIdentityMetadata,
        endpoint: String,
        pairingCode: String,
        certificatePinning: CertificatePinningMetadata,
        expiresAt: Date,
        nonce: String,
        schema: String = "macland-pairing"
    ) {
        self.schema = schema
        self.protocolVersion = protocolVersion
        self.hostIdentity = hostIdentity
        self.endpoint = endpoint
        self.pairingCode = pairingCode
        self.certificatePinning = certificatePinning
        self.expiresAt = expiresAt
        self.nonce = nonce
    }
}

public struct HostHelloPayload: Codable, Equatable, Sendable {
    public var hostID: UUID
    public var hostName: String
    public var hostVersion: String
    public var supportedVersions: [ProtocolVersion]
    public var capabilities: Capabilities
    public var permissionState: PermissionState
    public var hostIdentity: DeviceIdentityMetadata?
    public var certificatePinning: CertificatePinningMetadata?

    public init(
        hostID: UUID,
        hostName: String,
        hostVersion: String,
        supportedVersions: [ProtocolVersion] = [.current],
        capabilities: Capabilities = Capabilities(),
        permissionState: PermissionState = PermissionState(),
        hostIdentity: DeviceIdentityMetadata? = nil,
        certificatePinning: CertificatePinningMetadata? = nil
    ) {
        self.hostID = hostID
        self.hostName = hostName
        self.hostVersion = hostVersion
        self.supportedVersions = supportedVersions
        self.capabilities = capabilities
        self.permissionState = permissionState
        self.hostIdentity = hostIdentity
        self.certificatePinning = certificatePinning
    }
}

public struct PairingRequestPayload: Codable, Equatable, Sendable {
    public var clientID: UUID
    public var clientName: String
    public var pairingCode: String
    public var clientIdentity: DeviceIdentityMetadata?
    public var certificatePinning: CertificatePinningMetadata?

    public init(
        clientID: UUID,
        clientName: String,
        pairingCode: String,
        clientIdentity: DeviceIdentityMetadata? = nil,
        certificatePinning: CertificatePinningMetadata? = nil
    ) {
        self.clientID = clientID
        self.clientName = clientName
        self.pairingCode = pairingCode
        self.clientIdentity = clientIdentity
        self.certificatePinning = certificatePinning
    }

    private enum CodingKeys: String, CodingKey {
        case clientID
        case clientName
        case pairingCode
        case clientIdentity
        case certificatePinning
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        clientID = try container.decode(UUID.self, forKey: .clientID)
        clientName = try container.decode(String.self, forKey: .clientName)
        pairingCode = try container.decode(String.self, forKey: .pairingCode)
        clientIdentity = try container.decodeIfPresent(DeviceIdentityMetadata.self, forKey: .clientIdentity)
        certificatePinning = try container.decodeIfPresent(CertificatePinningMetadata.self, forKey: .certificatePinning)
    }
}

public struct PairingResponsePayload: Codable, Equatable, Sendable {
    public var accepted: Bool
    public var clientID: UUID
    public var hostID: UUID
    public var reason: String?
    public var hostIdentity: DeviceIdentityMetadata?
    public var certificatePinning: CertificatePinningMetadata?

    public init(
        accepted: Bool,
        clientID: UUID,
        hostID: UUID,
        reason: String? = nil,
        hostIdentity: DeviceIdentityMetadata? = nil,
        certificatePinning: CertificatePinningMetadata? = nil
    ) {
        self.accepted = accepted
        self.clientID = clientID
        self.hostID = hostID
        self.reason = reason
        self.hostIdentity = hostIdentity
        self.certificatePinning = certificatePinning
    }

    private enum CodingKeys: String, CodingKey {
        case accepted
        case clientID
        case hostID
        case reason
        case hostIdentity
        case certificatePinning
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accepted = try container.decode(Bool.self, forKey: .accepted)
        clientID = try container.decode(UUID.self, forKey: .clientID)
        hostID = try container.decode(UUID.self, forKey: .hostID)
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        hostIdentity = try container.decodeIfPresent(DeviceIdentityMetadata.self, forKey: .hostIdentity)
        certificatePinning = try container.decodeIfPresent(CertificatePinningMetadata.self, forKey: .certificatePinning)
    }
}

public struct SessionStartPayload: Codable, Equatable, Sendable {
    public var sessionID: UUID
    public var clientID: UUID
    public var displayID: UUID

    public init(sessionID: UUID, clientID: UUID, displayID: UUID) {
        self.sessionID = sessionID
        self.clientID = clientID
        self.displayID = displayID
    }
}

public struct SessionResumePayload: Codable, Equatable, Sendable {
    public var sessionID: UUID
    public var clientID: UUID
    public var resumeToken: String
    public var lastReceivedSequence: UInt64
    public var lastSentSequence: UInt64

    public init(
        sessionID: UUID,
        clientID: UUID,
        resumeToken: String,
        lastReceivedSequence: UInt64,
        lastSentSequence: UInt64
    ) {
        self.sessionID = sessionID
        self.clientID = clientID
        self.resumeToken = resumeToken
        self.lastReceivedSequence = lastReceivedSequence
        self.lastSentSequence = lastSentSequence
    }
}

public struct SessionResumeResponsePayload: Codable, Equatable, Sendable {
    public var accepted: Bool
    public var sessionID: UUID
    public var nextSequence: UInt64
    public var reason: String?

    public init(accepted: Bool, sessionID: UUID, nextSequence: UInt64, reason: String? = nil) {
        self.accepted = accepted
        self.sessionID = sessionID
        self.nextSequence = nextSequence
        self.reason = reason
    }
}

public enum SessionEndReason: String, Codable, CaseIterable, Sendable {
    case clientClosed = "client_closed"
    case hostClosed = "host_closed"
    case timeout
    case error
}

public struct SessionEndPayload: Codable, Equatable, Sendable {
    public var sessionID: UUID
    public var reason: SessionEndReason

    public init(sessionID: UUID, reason: SessionEndReason) {
        self.sessionID = sessionID
        self.reason = reason
    }
}

public struct DisplayDescriptor: Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var scaleFactor: Double
    public var refreshRate: Double?

    public init(
        id: UUID,
        name: String,
        pixelWidth: Int,
        pixelHeight: Int,
        scaleFactor: Double = 1,
        refreshRate: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.scaleFactor = scaleFactor
        self.refreshRate = refreshRate
    }
}

public struct DisplayStatePayload: Codable, Equatable, Sendable {
    public var displays: [DisplayDescriptor]
    public var selectedDisplayID: UUID?

    public init(displays: [DisplayDescriptor], selectedDisplayID: UUID? = nil) {
        self.displays = displays
        self.selectedDisplayID = selectedDisplayID
    }
}

public enum DisplayOrientation: String, Codable, CaseIterable, Sendable {
    case portrait
    case landscape
}

public struct DisplayCreatePayload: Codable, Equatable, Sendable {
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var scaleFactor: Double
    public var orientation: DisplayOrientation
    public var refreshRate: Double?

    public init(
        pixelWidth: Int,
        pixelHeight: Int,
        scaleFactor: Double = 1,
        orientation: DisplayOrientation,
        refreshRate: Double? = nil
    ) {
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.scaleFactor = scaleFactor
        self.orientation = orientation
        self.refreshRate = refreshRate
    }
}

public struct ApplicationDescriptor: Codable, Equatable, Sendable {
    public var bundleIdentifier: String
    public var name: String
    public var isRunning: Bool
    public var processID: Int32?

    public init(bundleIdentifier: String, name: String, isRunning: Bool = false, processID: Int32? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.isRunning = isRunning
        self.processID = processID
    }
}

public struct AppsListPayload: Codable, Equatable, Sendable {
    public var applications: [ApplicationDescriptor]

    public init(applications: [ApplicationDescriptor]) {
        self.applications = applications
    }
}

public struct ApplicationCommandPayload: Codable, Equatable, Sendable {
    public var bundleIdentifier: String
    public var displayID: UUID?

    public init(bundleIdentifier: String, displayID: UUID? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.displayID = displayID
    }
}

public enum SessionState: String, Codable, CaseIterable, Sendable {
    case negotiating
    case running
    case reconnecting
    case ended
}

public struct SessionStatePayload: Codable, Equatable, Sendable {
    public var sessionID: UUID
    public var state: SessionState
    public var displayID: UUID?

    public init(sessionID: UUID, state: SessionState, displayID: UUID? = nil) {
        self.sessionID = sessionID
        self.state = state
        self.displayID = displayID
    }
}

public enum ApplicationLifecycleEvent: String, Codable, CaseIterable, Sendable {
    case launched
    case terminated
    case suspended
    case resumed
    case focused
    case unfocused
}

public struct AppLifecyclePayload: Codable, Equatable, Sendable {
    public var event: ApplicationLifecycleEvent
    public var bundleIdentifier: String
    public var processID: Int32?

    public init(event: ApplicationLifecycleEvent, bundleIdentifier: String, processID: Int32? = nil) {
        self.event = event
        self.bundleIdentifier = bundleIdentifier
        self.processID = processID
    }
}

public enum InputEventKind: String, Codable, CaseIterable, Sendable {
    case pointerMove = "pointer.move"
    case pointerButton = "pointer.button"
    case scroll
    case key
    case text
}

public enum MouseButton: String, Codable, CaseIterable, Sendable {
    case left
    case right
    case middle
}

public enum InputModifier: String, Codable, CaseIterable, Sendable {
    case shift
    case control
    case option
    case command
    case capsLock = "caps_lock"
}

public struct InputPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct InputEvent: Codable, Equatable, Sendable {
    public var kind: InputEventKind
    public var timestamp: UInt64
    public var location: InputPoint?
    public var clickCount: Int?
    public var button: MouseButton?
    public var pressed: Bool?
    public var keyCode: UInt16?
    public var text: String?
    public var modifiers: [InputModifier]

    public init(
        kind: InputEventKind,
        timestamp: UInt64,
        location: InputPoint? = nil,
        button: MouseButton? = nil,
        pressed: Bool? = nil,
        keyCode: UInt16? = nil,
        text: String? = nil,
        modifiers: [InputModifier] = [],
        clickCount: Int? = nil
    ) {
        self.clickCount = clickCount
        self.kind = kind
        self.timestamp = timestamp
        self.location = location
        self.button = button
        self.pressed = pressed
        self.keyCode = keyCode
        self.text = text
        self.modifiers = modifiers
    }
}

public struct InputBatchPayload: Codable, Equatable, Sendable {
    public var batchID: UUID
    public var events: [InputEvent]

    public init(batchID: UUID, events: [InputEvent]) {
        self.batchID = batchID
        self.events = events
    }
}

public enum ClipboardOperation: String, Codable, CaseIterable, Sendable {
    case read
    case write
    case changed
}

public struct ClipboardPayload: Codable, Equatable, Sendable {
    public var operation: ClipboardOperation
    public var content: String?
    public var uniformTypeIdentifier: String?
    public var data: Data?

    public init(
        operation: ClipboardOperation,
        content: String? = nil,
        uniformTypeIdentifier: String? = nil,
        data: Data? = nil
    ) {
        self.operation = operation
        self.content = content
        self.uniformTypeIdentifier = uniformTypeIdentifier
        self.data = data
    }
}

public enum MediaNegotiationKind: String, Codable, CaseIterable, Sendable {
    case offer
    case answer
    case renegotiate
    case stop
}

public struct MediaCodec: Codable, Equatable, Sendable {
    public var name: String
    public var payloadType: Int
    public var clockRate: Int
    public var channels: Int?

    public init(name: String, payloadType: Int, clockRate: Int, channels: Int? = nil) {
        self.name = name
        self.payloadType = payloadType
        self.clockRate = clockRate
        self.channels = channels
    }
}

public struct MediaNegotiationPayload: Codable, Equatable, Sendable {
    public var kind: MediaNegotiationKind
    public var sessionID: UUID
    public var codecs: [MediaCodec]
    public var width: Int?
    public var height: Int?
    public var frameRate: Double?
    public var sdp: String?

    public init(
        kind: MediaNegotiationKind,
        sessionID: UUID,
        codecs: [MediaCodec] = [],
        width: Int? = nil,
        height: Int? = nil,
        frameRate: Double? = nil,
        sdp: String? = nil
    ) {
        self.kind = kind
        self.sessionID = sessionID
        self.codecs = codecs
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.sdp = sdp
    }
}

/// SDP is intentionally kept as an opaque protocol value here; WebRTC
/// implementation belongs outside the transport foundation.
public struct MediaSessionDescriptionPayload: Codable, Equatable, Sendable {
    public var sessionID: UUID
    public var sdp: String
    public var codecs: [MediaCodec]
    public var width: Int?
    public var height: Int?
    public var frameRate: Double?

    public init(
        sessionID: UUID,
        sdp: String,
        codecs: [MediaCodec] = [],
        width: Int? = nil,
        height: Int? = nil,
        frameRate: Double? = nil
    ) {
        self.sessionID = sessionID
        self.sdp = sdp
        self.codecs = codecs
        self.width = width
        self.height = height
        self.frameRate = frameRate
    }
}

public typealias MediaOfferPayload = MediaSessionDescriptionPayload
public typealias MediaAnswerPayload = MediaSessionDescriptionPayload

public struct MediaICEPayload: Codable, Equatable, Sendable {
    public var sessionID: UUID
    public var candidate: String
    public var sdpMid: String?
    public var sdpMLineIndex: Int32?
    public var usernameFragment: String?

    public init(
        sessionID: UUID,
        candidate: String,
        sdpMid: String? = nil,
        sdpMLineIndex: Int32? = nil,
        usernameFragment: String? = nil
    ) {
        self.sessionID = sessionID
        self.candidate = candidate
        self.sdpMid = sdpMid
        self.sdpMLineIndex = sdpMLineIndex
        self.usernameFragment = usernameFragment
    }
}

public enum HeartbeatKind: String, Codable, CaseIterable, Sendable {
    case ping
    case pong
}

public struct HeartbeatPayload: Codable, Equatable, Sendable {
    public var kind: HeartbeatKind
    public var heartbeatID: UUID
    public var sentAt: UInt64?
    public var acknowledgedSequence: UInt64?

    public init(
        kind: HeartbeatKind,
        heartbeatID: UUID,
        sentAt: UInt64? = nil,
        acknowledgedSequence: UInt64? = nil
    ) {
        self.kind = kind
        self.heartbeatID = heartbeatID
        self.sentAt = sentAt
        self.acknowledgedSequence = acknowledgedSequence
    }
}

public enum ControlErrorCode: String, Codable, CaseIterable, Sendable {
    case malformedMessage = "malformed_message"
    case malformedFrame = "malformed_frame"
    case unsupportedVersion = "unsupported_version"
    case unauthorized
    case pairingRequired = "pairing_required"
    case pairingRejected = "pairing_rejected"
    case certificatePinningFailed = "certificate_pinning_failed"
    case tlsIdentityNotConfigured = "tls_identity_not_configured"
    case unavailable
    case invalidState = "invalid_state"
    case sessionExpired = "session_expired"
    case reconnectRequired = "reconnect_required"
    case internalError = "internal_error"
}

public struct ErrorPayload: Codable, Equatable, Sendable {
    public var code: ControlErrorCode
    public var message: String
    public var retryable: Bool
    public var details: [String: String]?

    public init(code: ControlErrorCode, message: String, retryable: Bool = false, details: [String: String]? = nil) {
        self.code = code
        self.message = message
        self.retryable = retryable
        self.details = details
    }
}

public struct CapabilitiesPayload: Codable, Equatable, Sendable {
    public var capabilities: Capabilities

    public init(capabilities: Capabilities) {
        self.capabilities = capabilities
    }
}

public struct PermissionStatePayload: Codable, Equatable, Sendable {
    public var state: PermissionState

    public init(state: PermissionState) {
        self.state = state
    }
}
