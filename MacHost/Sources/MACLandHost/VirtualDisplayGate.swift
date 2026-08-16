import Foundation

enum VirtualDisplayStatus: Equatable {
    case blockedPublicAPI
    case experimentalPrivateAPI(String)
    case unavailable(reason: String)
    case ready

    var label: String {
        switch self {
        case .blockedPublicAPI:
            return "Blocked: no public API"
        case let .experimentalPrivateAPI(provider):
            return "Experimental: private (\(provider)) API"
        case let .unavailable(reason):
            return "Unavailable: \(reason)"
        case .ready:
            return "Ready"
        }
    }
}

enum VirtualDisplayGate {
    static func evaluate() -> VirtualDisplayStatus {
        // The public gate remains blocked. VoidDisplay is an explicitly
        // temporary private-API experiment selected by the user.
        if MACLandVoidDisplayRuntimeAvailable() {
            return .experimentalPrivateAPI("VoidDisplay")
        }
        return .unavailable(reason: "VoidDisplay private runtime is unavailable")
    }
}
