import Combine
import Foundation

public enum WorkspaceWindowKind: String, CaseIterable, Identifiable, Sendable {
    case remoteDisplay
    case settings

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .remoteDisplay:
            return "Remote Display"
        case .settings:
            return "Settings"
        }
    }

    public var systemImage: String {
        switch self {
        case .remoteDisplay:
            return "display"
        case .settings:
            return "gearshape"
        }
    }
}

public struct WorkspaceWindow: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let kind: WorkspaceWindowKind
    public var isMinimized: Bool

    public init(
        id: UUID = UUID(),
        kind: WorkspaceWindowKind,
        isMinimized: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.isMinimized = isMinimized
    }

    public var title: String { kind.title }
}

public enum ConnectionState: Equatable, Sendable {
    case disconnected
    case pairing(code: String)
    case connecting
    case connected(deviceName: String)

    public var label: String {
        switch self {
        case .disconnected:
            return "Not connected"
        case .pairing:
            return "Pairing"
        case .connecting:
            return "Connecting"
        case let .connected(deviceName):
            return "Connected to \(deviceName)"
        }
    }

    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

@MainActor
public final class WorkspaceState: ObservableObject {
    @Published public private(set) var windows: [WorkspaceWindow]
    @Published public private(set) var activeWindowID: WorkspaceWindow.ID?
    @Published public private(set) var connectionState: ConnectionState = .disconnected
    @Published public private(set) var connectionError: String?
    @Published public private(set) var mediaState = RemoteMediaState()
    @Published public var isLauncherPresented = false
    @Published public var isTaskSwitcherPresented = false
    @Published public var isRemoteFullscreen = false
    @Published public var launcherQuery = ""
    @Published public var pairingPayloadJSON = ""
    public let controlClient: MACLandControlClient
    public let discovery = MACLandBonjourDiscovery()

    public init(initialWindows: [WorkspaceWindow] = [WorkspaceWindow(kind: .remoteDisplay)]) {
        let controlClient = MACLandControlClient()
        self.controlClient = controlClient
        windows = initialWindows
        activeWindowID = initialWindows.first?.id
        mediaState = RemoteMediaState(webRTCClient: controlClient.webRTCClient)

        controlClient.onStateChange = { [weak self] state in
            guard let self else { return }
            switch state {
            case .connecting:
                connectionState = .connecting
                connectionError = nil
            case .pairing:
                connectionState = .pairing(code: controlClient.pairingCode)
                connectionError = nil
            case .connected:
                connectionState = .connected(deviceName: controlClient.hostName)
                connectionError = nil
                isRemoteFullscreen = true
            case .reconnecting:
                connectionState = .connecting
                mediaState.markReconnecting()
            case .failed:
                connectionState = .disconnected
                connectionError = controlClient.lastError
                isRemoteFullscreen = false
                if let error = controlClient.lastError {
                    mediaState.markFailed(error)
                }
            case .idle:
                connectionState = .disconnected
                isRemoteFullscreen = false
            }
        }
        controlClient.onSessionState = { [weak self] payload in
            guard let self else { return }
            switch payload.state {
            case .negotiating:
                mediaState.beginNegotiation()
            case .running:
                mediaState.markConnected()
            case .reconnecting:
                mediaState.markReconnecting()
            case .ended:
                mediaState.reset()
            }
        }
        controlClient.onDisplayState = { [weak self] payload in
            guard let self,
                  let selectedID = payload.selectedDisplayID,
                  let display = payload.displays.first(where: { $0.id == selectedID }) else { return }
            mediaState.updateDisplaySize(width: display.pixelWidth, height: display.pixelHeight)
        }
    }

    public var activeWindow: WorkspaceWindow? {
        guard let activeWindowID else { return nil }
        return windows.first { $0.id == activeWindowID }
    }

    public var visibleWindows: [WorkspaceWindow] {
        windows.filter { !$0.isMinimized }
    }

    public func openWindow(_ kind: WorkspaceWindowKind) {
        if let existingIndex = windows.firstIndex(where: { $0.kind == kind }) {
            windows[existingIndex].isMinimized = false
            activeWindowID = windows[existingIndex].id
        } else {
            let newWindow = WorkspaceWindow(kind: kind)
            windows.append(newWindow)
            activeWindowID = newWindow.id
        }

        isLauncherPresented = false
        isTaskSwitcherPresented = false
    }

    public func focusWindow(_ id: WorkspaceWindow.ID) {
        guard let index = windows.firstIndex(where: { $0.id == id }) else { return }
        windows[index].isMinimized = false
        activeWindowID = id
        isTaskSwitcherPresented = false
    }

    public func minimizeWindow(_ id: WorkspaceWindow.ID) {
        guard let index = windows.firstIndex(where: { $0.id == id }) else { return }
        windows[index].isMinimized = true
        if activeWindowID == id {
            activeWindowID = windows.first(where: { !$0.isMinimized && $0.id != id })?.id
        }
    }

    public func closeWindow(_ id: WorkspaceWindow.ID) {
        guard let closingIndex = windows.firstIndex(where: { $0.id == id }) else { return }
        windows.remove(at: closingIndex)

        if activeWindowID == id {
            activeWindowID = visibleWindows.first?.id ?? windows.first?.id
        }
    }

    public func presentLauncher() {
        launcherQuery = ""
        isLauncherPresented = true
        isTaskSwitcherPresented = false
    }

    public func dismissLauncher() {
        isLauncherPresented = false
        launcherQuery = ""
    }

    public func toggleTaskSwitcher() {
        isTaskSwitcherPresented.toggle()
        isLauncherPresented = false
    }

    public func beginPairing() {
        discovery.start()
        connectionError = nil
        connectionState = .pairing(code: "")
    }

    public func beginConnection() {
        guard case .pairing = connectionState else { return }
        connectionState = .connecting
        mediaState.beginNegotiation()
    }

    public func connect(deviceName: String) {
        connectionState = .connected(deviceName: deviceName)
        mediaState.markConnected()
    }

    public func connect(using pairingPayload: PairingQRCodePayload) {
        connectionState = .connecting
        connectionError = nil
        mediaState.beginNegotiation()
        do {
            try controlClient.connect(using: pairingPayload)
        } catch {
            connectionState = .disconnected
            connectionError = error.localizedDescription
            mediaState.markFailed(error.localizedDescription)
        }
    }

    public func connectFromPairingJSON() {
        guard let data = pairingPayloadJSON.data(using: .utf8) else {
            connectionError = "Pairing data is not valid UTF-8."
            mediaState.markFailed("Pairing data is not valid UTF-8.")
            return
        }
        do {
            let payload = try MACLandJSON.makeDecoder().decode(PairingQRCodePayload.self, from: data)
            connect(using: payload)
        } catch {
            connectionError = "Pairing data could not be decoded: " + error.localizedDescription
            mediaState.markFailed("Pairing data could not be decoded: " + error.localizedDescription)
        }
    }

    public func reconnect() {
        controlClient.reconnect()
        if controlClient.state == .reconnecting {
            connectionState = .connecting
            connectionError = nil
            mediaState.beginNegotiation()
        } else {
            beginPairing()
        }
    }

    public func sendTouch(_ touch: RemoteTouchPoint) {
        guard connectionState.isConnected else { return }
        let event = InputEvent(
            kind: .pointerMove,
            timestamp: UInt64(Date().timeIntervalSince1970 * 1_000),
            location: InputPoint(x: touch.remote.x, y: touch.remote.y)
        )
        try? controlClient.sendInput(events: [event])
    }

    public func disconnect() {
        controlClient.disconnect()
        discovery.stop()
        connectionState = .disconnected
        connectionError = nil
        isRemoteFullscreen = false
        mediaState.reset()
    }
}
