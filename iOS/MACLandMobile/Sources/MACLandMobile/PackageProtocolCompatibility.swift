#if SWIFT_PACKAGE
import Foundation

// The Xcode application target compiles the canonical shared protocol files
// from ../../Shared/MACLandProtocol. SwiftPM does not allow a target to point
// outside its package root, so the standalone package test harness uses this
// deliberately small wire-compatible mirror for compile/test coverage.

public struct ProtocolVersion: Codable, Comparable, Hashable, Sendable {
    public let major: Int
    public let minor: Int
    public static let current = ProtocolVersion(major: 1, minor: 0)
    public init(major: Int, minor: Int) { self.major = major; self.minor = minor }
    public static func < (lhs: Self, rhs: Self) -> Bool { (lhs.major, lhs.minor) < (rhs.major, rhs.minor) }
}

public enum ControlMessageKind: String, Codable, Sendable {
    case hostHello = "host.hello"
    case pairingRequest = "pair.request"
    case pairingResponse = "pair.accept"
    case sessionStart = "session.start"
    case sessionState = "session.state"
    case displayState = "display.state"
    case appsList = "apps.list"
    case appLaunch = "app.launch"
    case appFocus = "app.focus"
    case appClose = "app.close"
    case inputBatch = "input.batch"
    case mediaOffer = "media.offer"
    case mediaAnswer = "media.answer"
    case mediaICE = "media.ice"
    case heartbeat
    case error
}

public enum MACLandJSON {
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public struct ControlEnvelope<Payload: Codable & Sendable>: Codable, Sendable {
    public let version: ProtocolVersion
    public let kind: ControlMessageKind
    public let id: UUID
    public let sequence: UInt64
    public let requestID: UUID?
    public let payload: Payload

    public init(
        version: ProtocolVersion = .current,
        kind: ControlMessageKind,
        id: UUID = UUID(),
        sequence: UInt64,
        requestID: UUID? = nil,
        payload: Payload
    ) {
        self.version = version
        self.kind = kind
        self.id = id
        self.sequence = sequence
        self.requestID = requestID
        self.payload = payload
    }

    public static func decode(
        from data: Data,
        expectedKind: ControlMessageKind? = nil,
        using decoder: JSONDecoder = MACLandJSON.makeDecoder()
    ) throws -> Self {
        let envelope = try decoder.decode(Self.self, from: data)
        if let expectedKind, envelope.kind != expectedKind { throw NSError(domain: "MACLandProtocol", code: 1) }
        return envelope
    }
}

public struct ControlFrameCodec: Sendable {
    public init(maximumFrameSize: Int = 1_048_576) {}
    public func encode<Payload: Codable & Sendable>(_ envelope: ControlEnvelope<Payload>, using encoder: JSONEncoder = MACLandJSON.makeEncoder()) throws -> Data {
        try encoder.encode(envelope)
    }
}

public enum DevicePlatform: String, Codable, Sendable { case macOS = "macos"; case iOS = "ios"; case unknown }
public struct DeviceIdentityMetadata: Codable, Equatable, Sendable {
    public var deviceID: UUID
    public var deviceName: String
    public var platform: DevicePlatform
    public var appVersion: String
    public var publicKeySHA256: String?
    public init(deviceID: UUID, deviceName: String, platform: DevicePlatform, appVersion: String, publicKeySHA256: String? = nil) {
        self.deviceID = deviceID; self.deviceName = deviceName; self.platform = platform; self.appVersion = appVersion; self.publicKeySHA256 = publicKeySHA256
    }
}
public enum CertificateDigestAlgorithm: String, Codable, Sendable { case sha256 }
public struct CertificatePinningMetadata: Codable, Equatable, Sendable {
    public var algorithm: CertificateDigestAlgorithm
    public var certificateSHA256: String
    public var publicKeySHA256: String?
    public init(algorithm: CertificateDigestAlgorithm = .sha256, certificateSHA256: String, publicKeySHA256: String? = nil) {
        self.algorithm = algorithm; self.certificateSHA256 = certificateSHA256; self.publicKeySHA256 = publicKeySHA256
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
    public init(protocolVersion: ProtocolVersion = .current, hostIdentity: DeviceIdentityMetadata, endpoint: String, pairingCode: String, certificatePinning: CertificatePinningMetadata, expiresAt: Date, nonce: String, schema: String = "macland-pairing") {
        self.schema = schema; self.protocolVersion = protocolVersion; self.hostIdentity = hostIdentity; self.endpoint = endpoint; self.pairingCode = pairingCode; self.certificatePinning = certificatePinning; self.expiresAt = expiresAt; self.nonce = nonce
    }
}

public enum Capability: String, Codable, Sendable { case displayEnumeration = "display.enumeration"; case screenCapture = "screen.capture"; case inputInjection = "input.injection"; case clipboardRead = "clipboard.read"; case clipboardWrite = "clipboard.write"; case audioCapture = "audio.capture"; case videoCapture = "video.capture" }
public struct Capabilities: Codable, Equatable, Sendable { public var values: [Capability]; public init(values: [Capability] = []) { self.values = values } }
public enum PermissionStatus: String, Codable, Sendable { case unknown; case notDetermined = "not_determined"; case denied; case granted; case restricted }
public struct PermissionState: Codable, Equatable, Sendable { public var screenRecording: PermissionStatus; public var accessibility: PermissionStatus; public var inputMonitoring: PermissionStatus; public var notifications: PermissionStatus }
public struct HostHelloPayload: Codable, Equatable, Sendable {
    public var hostID: UUID; public var hostName: String; public var hostVersion: String; public var supportedVersions: [ProtocolVersion]; public var capabilities: Capabilities; public var permissionState: PermissionState; public var hostIdentity: DeviceIdentityMetadata?; public var certificatePinning: CertificatePinningMetadata?
}
public struct PairingRequestPayload: Codable, Equatable, Sendable { public var clientID: UUID; public var clientName: String; public var pairingCode: String; public var clientIdentity: DeviceIdentityMetadata?; public var certificatePinning: CertificatePinningMetadata?; public init(clientID: UUID, clientName: String, pairingCode: String, clientIdentity: DeviceIdentityMetadata? = nil, certificatePinning: CertificatePinningMetadata? = nil) { self.clientID = clientID; self.clientName = clientName; self.pairingCode = pairingCode; self.clientIdentity = clientIdentity; self.certificatePinning = certificatePinning } }
public struct PairingResponsePayload: Codable, Equatable, Sendable { public var accepted: Bool; public var clientID: UUID; public var hostID: UUID; public var reason: String?; public var hostIdentity: DeviceIdentityMetadata?; public var certificatePinning: CertificatePinningMetadata? }

public struct DisplayDescriptor: Codable, Equatable, Sendable { public var id: UUID; public var name: String; public var pixelWidth: Int; public var pixelHeight: Int; public var scaleFactor: Double; public var refreshRate: Double? }
public struct DisplayStatePayload: Codable, Equatable, Sendable { public var displays: [DisplayDescriptor]; public var selectedDisplayID: UUID? }
public struct ApplicationDescriptor: Codable, Equatable, Sendable { public var bundleIdentifier: String; public var name: String; public var isRunning: Bool; public var processID: Int32? }
public struct AppsListPayload: Codable, Equatable, Sendable { public var applications: [ApplicationDescriptor] }
public struct SessionStartPayload: Codable, Equatable, Sendable { public var sessionID: UUID; public var clientID: UUID; public var displayID: UUID; public init(sessionID: UUID, clientID: UUID, displayID: UUID) { self.sessionID = sessionID; self.clientID = clientID; self.displayID = displayID } }
public enum SessionState: String, Codable, Sendable { case negotiating; case running; case reconnecting; case ended }
public struct SessionStatePayload: Codable, Equatable, Sendable { public var sessionID: UUID; public var state: SessionState; public var displayID: UUID? }

public enum InputEventKind: String, Codable, Sendable { case pointerMove = "pointer.move"; case pointerButton = "pointer.button"; case scroll; case key; case text }
public enum MouseButton: String, Codable, Sendable { case left; case right; case middle }
public enum InputModifier: String, Codable, Sendable { case shift; case control; case option; case command; case capsLock = "caps_lock" }
public struct InputPoint: Codable, Equatable, Sendable { public var x: Double; public var y: Double; public init(x: Double, y: Double) { self.x = x; self.y = y } }
public struct InputEvent: Codable, Equatable, Sendable { public var kind: InputEventKind; public var timestamp: UInt64; public var location: InputPoint?; public var button: MouseButton?; public var pressed: Bool?; public var keyCode: UInt16?; public var text: String?; public var modifiers: [InputModifier]; public init(kind: InputEventKind, timestamp: UInt64, location: InputPoint? = nil, button: MouseButton? = nil, pressed: Bool? = nil, keyCode: UInt16? = nil, text: String? = nil, modifiers: [InputModifier] = []) { self.kind = kind; self.timestamp = timestamp; self.location = location; self.button = button; self.pressed = pressed; self.keyCode = keyCode; self.text = text; self.modifiers = modifiers } }
public struct InputBatchPayload: Codable, Equatable, Sendable { public var batchID: UUID; public var events: [InputEvent]; public init(batchID: UUID, events: [InputEvent]) { self.batchID = batchID; self.events = events } }
public struct ApplicationCommandPayload: Codable, Equatable, Sendable { public var bundleIdentifier: String; public var displayID: UUID?; public init(bundleIdentifier: String, displayID: UUID? = nil) { self.bundleIdentifier = bundleIdentifier; self.displayID = displayID } }

public struct MediaSessionDescriptionPayload: Codable, Equatable, Sendable { public var sessionID: UUID; public var sdp: String; public var codecs: [String]; public var width: Int; public var height: Int; public var frameRate: Int; public init(sessionID: UUID, sdp: String, codecs: [String] = [], width: Int, height: Int, frameRate: Int) { self.sessionID = sessionID; self.sdp = sdp; self.codecs = codecs; self.width = width; self.height = height; self.frameRate = frameRate } }
public typealias MediaOfferPayload = MediaSessionDescriptionPayload
public typealias MediaAnswerPayload = MediaSessionDescriptionPayload
public struct MediaICEPayload: Codable, Equatable, Sendable { public var sessionID: UUID; public var candidate: String; public var sdpMid: String?; public var sdpMLineIndex: Int32?; public var usernameFragment: String?; public init(sessionID: UUID, candidate: String, sdpMid: String? = nil, sdpMLineIndex: Int32? = nil, usernameFragment: String? = nil) { self.sessionID = sessionID; self.candidate = candidate; self.sdpMid = sdpMid; self.sdpMLineIndex = sdpMLineIndex; self.usernameFragment = usernameFragment } }
public enum HeartbeatKind: String, Codable, Sendable { case ping; case pong }
public struct HeartbeatPayload: Codable, Equatable, Sendable { public var kind: HeartbeatKind; public var heartbeatID: UUID; public var sentAt: UInt64?; public var acknowledgedSequence: UInt64? }
public enum ControlErrorCode: String, Codable, Sendable { case malformedMessage = "malformed_message"; case malformedFrame = "malformed_frame"; case unsupportedVersion = "unsupported_version"; case unauthorized; case pairingRequired = "pairing_required"; case pairingRejected = "pairing_rejected"; case certificatePinningFailed = "certificate_pinning_failed"; case tlsIdentityNotConfigured = "tls_identity_not_configured"; case unavailable; case invalidState = "invalid_state"; case sessionExpired = "session_expired"; case reconnectRequired = "reconnect_required"; case internalError = "internal_error" }
public struct ErrorPayload: Codable, Equatable, Sendable { public var code: ControlErrorCode; public var message: String; public var retryable: Bool; public var details: [String: String]? }
#endif
