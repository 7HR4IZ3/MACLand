import Foundation

public enum ControlMessageKind: String, Codable, CaseIterable, Sendable {
    case hostHello = "host.hello"
    case pairingQRCode = "pair.qr"
    case pairingRequest = "pair.request"
    case pairingResponse = "pair.accept"
    case sessionStart = "session.start"
    case sessionResume = "session.resume"
    case sessionResumeResponse = "session.resume.accept"
    case sessionState = "session.state"
    case sessionEnd = "session.end"
    case displayCreate = "display.create"
    case displayState = "display.state"
    case appsList = "apps.list"
    case windowsList = "windows.list"
    case windowCommand = "window.command"
    case appLaunch = "app.launch"
    case appFocus = "app.focus"
    case appClose = "app.close"
    case appLifecycle = "app.lifecycle"
    case inputBatch = "input.batch"
    case clipboard = "clipboard"
    case clipboardGet = "clipboard.get"
    case clipboardSet = "clipboard.set"
    case mediaNegotiation = "media.negotiate"
    case mediaOffer = "media.offer"
    case mediaAnswer = "media.answer"
    case mediaICE = "media.ice"
    case heartbeat = "heartbeat"
    case error = "error"
    case capabilities = "capabilities"
    case permissionState = "permission.state"
}

public enum ControlEnvelopeError: Error, Equatable, Sendable, CustomStringConvertible {
    case unexpectedKind(expected: ControlMessageKind, actual: ControlMessageKind)

    public var description: String {
        switch self {
        case let .unexpectedKind(expected, actual):
            return "Unexpected control message kind \(actual.rawValue); expected \(expected.rawValue)"
        }
    }
}

public enum ControlFrameError: Error, Equatable, Sendable, CustomStringConvertible {
    case empty
    case tooLarge(actual: Int, maximum: Int)

    public var description: String {
        switch self {
        case .empty:
            return "Control frame is empty"
        case let .tooLarge(actual, maximum):
            return "Control frame is \(actual) bytes; maximum is \(maximum) bytes"
        }
    }
}

public struct ControlEnvelope<Payload: Codable & Sendable>: Codable, Sendable {
    public static var supportedProtocolVersions: [ProtocolVersion] { [.current] }

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
    ) throws {
        try version.validate(supportedBy: Self.supportedProtocolVersions)
        self.version = version
        self.kind = kind
        self.id = id
        self.sequence = sequence
        self.requestID = requestID
        self.payload = payload
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(ProtocolVersion.self, forKey: .version)
        try version.validate(supportedBy: Self.supportedProtocolVersions)
        self.version = version
        self.kind = try container.decode(ControlMessageKind.self, forKey: .kind)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.sequence = try container.decode(UInt64.self, forKey: .sequence)
        self.requestID = try container.decodeIfPresent(UUID.self, forKey: .requestID)
        self.payload = try container.decode(Payload.self, forKey: .payload)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(kind, forKey: .kind)
        try container.encode(id, forKey: .id)
        try container.encode(sequence, forKey: .sequence)
        try container.encodeIfPresent(requestID, forKey: .requestID)
        try container.encode(payload, forKey: .payload)
    }

    public func validate(expectedKind: ControlMessageKind) throws {
        guard kind == expectedKind else {
            throw ControlEnvelopeError.unexpectedKind(expected: expectedKind, actual: kind)
        }
    }

    public static func decode(
        from data: Data,
        expectedKind: ControlMessageKind? = nil,
        using decoder: JSONDecoder = MACLandJSON.makeDecoder()
    ) throws -> Self {
        let envelope = try decoder.decode(Self.self, from: data)
        if let expectedKind {
            try envelope.validate(expectedKind: expectedKind)
        }
        return envelope
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case kind
        case id
        case sequence
        case requestID = "request_id"
        case payload
    }
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

/// Encodes one JSON control envelope per WebSocket message.
///
/// Network.framework owns the WebSocket wire framing. This codec provides the
/// shared message-size boundary and keeps all envelope encoding consistent on
/// both platforms.
public struct ControlFrameCodec: Sendable {
    public static let defaultMaximumFrameSize = 1_048_576

    public let maximumFrameSize: Int

    public init(maximumFrameSize: Int = ControlFrameCodec.defaultMaximumFrameSize) {
        precondition(maximumFrameSize > 0, "A control frame limit must be positive")
        self.maximumFrameSize = maximumFrameSize
    }

    public func encode<Payload: Codable & Sendable>(
        _ envelope: ControlEnvelope<Payload>,
        using encoder: JSONEncoder = MACLandJSON.makeEncoder()
    ) throws -> Data {
        let data = try encoder.encode(envelope)
        guard data.count <= maximumFrameSize else {
            throw ControlFrameError.tooLarge(actual: data.count, maximum: maximumFrameSize)
        }
        return data
    }

    public func decode<Payload: Codable & Sendable>(
        _ data: Data,
        as payloadType: Payload.Type = Payload.self,
        expectedKind: ControlMessageKind? = nil,
        using decoder: JSONDecoder = MACLandJSON.makeDecoder()
    ) throws -> ControlEnvelope<Payload> {
        guard !data.isEmpty else { throw ControlFrameError.empty }
        guard data.count <= maximumFrameSize else {
            throw ControlFrameError.tooLarge(actual: data.count, maximum: maximumFrameSize)
        }
        return try ControlEnvelope<Payload>.decode(from: data, expectedKind: expectedKind, using: decoder)
    }
}
