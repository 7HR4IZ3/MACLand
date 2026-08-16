import Foundation

public struct ProtocolVersion: Codable, Comparable, CustomStringConvertible, Hashable, Sendable {
    public let major: Int
    public let minor: Int

    public static let current = ProtocolVersion(major: 1, minor: 0)

    public init(major: Int, minor: Int) {
        precondition(major >= 0 && minor >= 0, "Protocol versions cannot be negative")
        self.major = major
        self.minor = minor
    }

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 2,
              let major = Int(components[0]),
              let minor = Int(components[1]),
              major >= 0,
              minor >= 0 else {
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Protocol version must be a non-negative major.minor string"
            )
        }
        self.init(major: major, minor: minor)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    public var description: String { "\(major).\(minor)" }

    public static func < (lhs: ProtocolVersion, rhs: ProtocolVersion) -> Bool {
        (lhs.major, lhs.minor) < (rhs.major, rhs.minor)
    }

    /// Minor versions are backward-compatible; a major-version mismatch is never compatible.
    public func isCompatible(with supportedVersion: ProtocolVersion = .current) -> Bool {
        major == supportedVersion.major && minor <= supportedVersion.minor
    }

    public func validate(supportedBy supportedVersions: [ProtocolVersion] = [.current]) throws {
        guard supportedVersions.contains(where: { isCompatible(with: $0) }) else {
            throw ProtocolVersionError.unsupported(version: self, supportedVersions: supportedVersions)
        }
    }
}

public enum ProtocolVersionError: Error, Equatable, Sendable, CustomStringConvertible {
    case unsupported(version: ProtocolVersion, supportedVersions: [ProtocolVersion])

    public var description: String {
        switch self {
        case let .unsupported(version, supportedVersions):
            let supported = supportedVersions.map(\.description).joined(separator: ", ")
            return "Unsupported protocol version \(version); supported versions: \(supported)"
        }
    }
}

public enum ControlTransportError: Error, Equatable, Sendable, CustomStringConvertible {
    case invalidState
    case pairingRequired
    case pairingRejected
    case certificatePinningFailed
    case tlsIdentityNotConfigured
    case connectionFailed(String)
    case sessionClosed

    public var description: String {
        switch self {
        case .invalidState: "The control session is in an invalid state for this operation."
        case .pairingRequired: "The control session must be paired before commands are accepted."
        case .pairingRejected: "The control session pairing request was rejected."
        case .certificatePinningFailed: "The peer certificate did not satisfy the configured pin."
        case .tlsIdentityNotConfigured: "A TLS identity has not been provisioned for the control listener."
        case let .connectionFailed(reason): "The control connection failed: \(reason)"
        case .sessionClosed: "The control session is closed."
        }
    }
}

public enum ControlTransportState: Equatable, Sendable {
    case idle
    case connecting
    case awaitingPairing
    case established(sessionID: UUID)
    case reconnecting(sessionID: UUID)
    case resuming(sessionID: UUID)
    case closing
    case closed
    case failed(ControlTransportError)
}

public enum ControlTransportEvent: Sendable {
    case start
    case transportReady
    case pairingAccepted(sessionID: UUID)
    case pairingRejected
    case transportInterrupted
    case resumeAccepted(sessionID: UUID)
    case resumeRejected
    case closeRequested
    case closed
    case failed(ControlTransportError)
}

/// Pure state transitions keep reconnect/resume behavior testable without
/// opening sockets or pretending that an unpaired connection is authorized.
public struct ControlTransportStateMachine: Sendable {
    public private(set) var state: ControlTransportState = .idle

    public init(state: ControlTransportState = .idle) {
        self.state = state
    }

    public mutating func apply(_ event: ControlTransportEvent) throws {
        let nextState: ControlTransportState?

        switch (state, event) {
        case (.idle, .start):
            nextState = .connecting
        case (.connecting, .transportReady):
            nextState = .awaitingPairing
        case (.awaitingPairing, let .pairingAccepted(sessionID)):
            nextState = .established(sessionID: sessionID)
        case (.awaitingPairing, .pairingRejected):
            nextState = .failed(.pairingRejected)
        case (.established(let sessionID), .transportInterrupted):
            nextState = .reconnecting(sessionID: sessionID)
        case (.reconnecting(let sessionID), .transportReady):
            nextState = .resuming(sessionID: sessionID)
        case (.resuming(let sessionID), let .resumeAccepted(resumedID)) where sessionID == resumedID:
            nextState = .established(sessionID: sessionID)
        case (.resuming, .resumeRejected):
            nextState = .awaitingPairing
        case (.idle, .closeRequested), (.connecting, .closeRequested),
             (.awaitingPairing, .closeRequested), (.established, .closeRequested),
             (.reconnecting, .closeRequested), (.resuming, .closeRequested):
            nextState = .closing
        case (.closing, .closeRequested):
            nextState = .closed
        case (.failed, .closed), (.closed, .closed):
            nextState = .closed
        case (.failed, .closeRequested):
            nextState = .closed
        case (_, let .failed(error)):
            nextState = .failed(error)
        default:
            throw ControlTransportError.invalidState
        }

        state = nextState!
    }
}
