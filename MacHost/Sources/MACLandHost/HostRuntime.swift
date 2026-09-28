import AppKit
import Combine
import Foundation
import OSLog

@MainActor
final class HostRuntime: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var controlStatus = "Not running"
    @Published private(set) var displayStatus: VirtualDisplayStatus = .blockedPublicAPI
    @Published private(set) var providerStatus: RemoteDisplayProviderStatus = .driverIntegrationRequired
    @Published private(set) var providerActionStatus = ""
    @Published private(set) var permissionSummary = "Permissions have not been checked."
    @Published private(set) var applications: [InstalledApplication] = []
    @Published private(set) var workspaceActionStatus = ""
    @Published private(set) var mediaStatus = "Media idle"
    @Published private(set) var pairingStatus = "Pairing is disabled"
    @Published private(set) var pairingCode = ""
    @Published private(set) var pairingPayloadJSON = ""
    @Published private(set) var isStarting = false
    @Published private(set) var isStopping = false
    @Published private(set) var isPairingReady = false

    let hostID: UUID
    let hostName: String
    private let hostNetworkName: String
    let permissionCenter: PermissionCenter
    let applicationCatalog: ApplicationCatalog
    let commandRouter: HostCommandRouter
    let launchAtLoginController: LaunchAtLoginController
    let displayProvider: ThirdPartyDisplayProvider

    var terminalControlEnabledForMenu: Bool { terminalControlEnabled }
    var pairingApprovalEnabledForMenu: Bool { pairingApproval.isEnabled }
    var isBusy: Bool { isStarting || isStopping }

    private let logger = Logger(subsystem: "com.thraize.macland.host", category: "runtime")
    private let tlsIdentityStore = KeychainTLSIdentityStore()
    private let pairingApproval = PairingApprovalStore()
    private let inputInjector = InputInjector()
    private var controlListener: LocalControlListener?
    private var windowController: ApplicationWindowController?
    private var mediaCoordinator: VoidDisplayMediaCoordinator?
    private var mediaSessionID: UUID?
    private var terminalControlEnabled = false

    init() {
        let currentHost = Host.current()
        hostID = UUID()
        hostName = currentHost.localizedName ?? currentHost.name ?? "Mac"
        hostNetworkName = currentHost.name ?? currentHost.localizedName ?? "macland-host"
        permissionCenter = PermissionCenter()
        applicationCatalog = ApplicationCatalog()
        commandRouter = HostCommandRouter()
        launchAtLoginController = LaunchAtLoginController()
        displayProvider = ThirdPartyDisplayProvider(
            driver: VoidDisplayDriverAdapter()
        )
        displayStatus = VirtualDisplayGate.evaluate()
        displayProvider.refresh()
        providerStatus = displayProvider.status
        refreshApplications()
        refreshPermissions()
    }

    var capabilities: Capabilities {
        var values: [Capability] = []
        if permissionCenter.state.screenRecording == .granted {
            values.append(.screenCapture)
        }
        if permissionCenter.state.accessibility == .granted {
            values.append(.inputInjection)
        }
        return Capabilities(values: values)
    }

    func start() {
        guard !isRunning, !isStarting, !isStopping else { return }

        isStarting = true
        isPairingReady = false
        pairingCode = ""
        pairingPayloadJSON = ""
        pairingStatus = "Preparing secure host…"
        providerActionStatus = "Preparing remote desktop…"

        do {
            let tlsMaterial = try tlsIdentityStore.load()
            let listener = try LocalControlListener(
                hostName: hostName,
                certificatePinningMetadata: tlsMaterial.certificatePinning,
                tlsIdentityFactory: { tlsMaterial.identity },
                hostID: hostID,
                capabilities: capabilities,
                permissionState: permissionCenter.state,
                pairingApproval: pairingApproval,
                onSessionStart: { [weak self] _ in
                    Task { @MainActor in
                        self?.sendCurrentDisplayState()
                        self?.startMediaCapture()
                        self?.broadcastWindowsList()
                    }
                },
                onMediaAnswer: { [weak self] answer in
                    Task { @MainActor in
                        self?.applyMediaAnswer(sdp: answer.sdp)
                    }
                },
                onMediaICE: { [weak self] candidate in
                    Task { @MainActor in
                        self?.applyMediaICE(candidate)
                    }
                },
                onAppLaunch: { [weak self] command in
                    Task { @MainActor in self?.launchApplication(bundleIdentifier: command.bundleIdentifier) }
                },
                onAppFocus: { [weak self] command in
                    Task { @MainActor in self?.focusApplication(bundleIdentifier: command.bundleIdentifier) }
                },
                onAppClose: { [weak self] command in
                    Task { @MainActor in self?.closeApplication(bundleIdentifier: command.bundleIdentifier) }
                },
                onWindowCommand: { [weak self] command in
                    Task { @MainActor in self?.handleWindowCommand(command) }
                },
                onWindowsListRequest: { [weak self] in
                    Task { @MainActor in self?.broadcastWindowsList() }
                },
                onInputBatch: { [weak self] batch in
                    Task { @MainActor in self?.inject(batch: batch) }
                },
                appsListProvider: { [weak self] in
                    self?.appsListPayload() ?? AppsListPayload(applications: [])
                }
            )
            listener.start()
            controlListener = listener
            isRunning = true
            controlStatus = "Advertising secure WebSocket on LAN"
            pairingApproval.setEnabled(true)
            pairingCode = listener.pairingCode
            pairingStatus = "Pairing is ready. Code: " + listener.pairingCode
            pairingPayloadJSON = makePairingPayloadJSON(
                certificatePinning: tlsMaterial.certificatePinning,
                pairingCode: listener.pairingCode,
                expiresAt: listener.pairingExpiresAt
            )
            logger.info("Host started with id \(self.hostID.uuidString, privacy: .public)")

            Task { @MainActor [weak self] in
                guard let self else { return }

                do {
                    try await createRemoteDisplayIfNeeded()
                    isStarting = false
                    isPairingReady = true
                    providerActionStatus = "Remote desktop ready."
                    pairingStatus = "Pairing is ready. Code: " + pairingCode
                } catch {
                    isStarting = false
                    providerActionStatus = "Host is running, but the remote desktop could not be created: " + error.localizedDescription
                    logger.error("Automatic remote display creation failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        } catch {
            isStarting = false
            let recovery = (error as? TLSIdentityStoreError)?.recoverySuggestion
            controlStatus = [
                "Unavailable: \(error.localizedDescription)",
                recovery
            ]
            .compactMap { $0 }
            .joined(separator: " ")
            providerActionStatus = controlStatus
            pairingStatus = "Pairing is unavailable until the host is fixed."
            logger.error("Host failed to start: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stop() {
        guard isRunning || isStarting else { return }

        isStarting = false
        isStopping = true
        isPairingReady = false
        controlListener?.stop()
        controlListener = nil

        Task { @MainActor [weak self] in
            guard let self else { return }

            if let mediaCoordinator {
                await mediaCoordinator.stop()
                self.mediaCoordinator = nil
            }

            var teardownError: String?
            do {
                try await displayProvider.destroy()
                providerStatus = displayProvider.status
            } catch {
                teardownError = "Host stopped, but the remote desktop could not be removed: " + error.localizedDescription
                logger.error("Remote display teardown failed: \(error.localizedDescription, privacy: .public)")
            }

            windowController = nil
            isRunning = false
            isStopping = false
            controlStatus = "Not running"
            pairingApproval.setEnabled(false)
            pairingStatus = "Pairing is disabled"
            pairingCode = ""
            pairingPayloadJSON = ""
            mediaStatus = "Media idle"
            providerActionStatus = teardownError ?? "Host stopped."
            logger.info("Host stopped")
        }
    }

    func toggleHost() {
        if isRunning {
            stop()
        } else {
            start()
        }
    }

    func refreshApplications() {
        applicationCatalog.refresh()
        applications = applicationCatalog.applications
    }

    func refreshPermissions() {
        permissionCenter.refresh()
        permissionSummary = permissionCenter.summary
    }

    func openPermissionSettings() {
        permissionCenter.openSettings()
    }

    func refreshDisplayProvider() {
        displayProvider.refresh()
        providerStatus = displayProvider.status
    }

    func createRemoteDisplay() {
        Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                try await createRemoteDisplayIfNeeded()
                providerActionStatus = "Remote display created."
            } catch {
                providerActionStatus = error.localizedDescription
                providerStatus = .unavailable(error.localizedDescription)
                logger.error("Remote display creation failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func createRemoteDisplayIfNeeded() async throws {
        guard displayProvider.activeDisplayID == nil else {
            providerStatus = displayProvider.status
            configureWindowController()
            return
        }

        try await displayProvider.create(
            configuration: ThirdPartyDisplayConfiguration(
                pixelWidth: 1080,
                pixelHeight: 1920,
                orientation: .portrait
            )
        )
        providerStatus = displayProvider.status
        configureWindowController()
    }

    func destroyRemoteDisplay() {
        Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                if let mediaCoordinator {
                    await mediaCoordinator.stop()
                    self.mediaCoordinator = nil
                    mediaStatus = "Media stopped"
                }
                try await displayProvider.destroy()
                providerStatus = displayProvider.status
                windowController = nil
                providerActionStatus = "Remote display destroyed."
            } catch {
                providerActionStatus = error.localizedDescription
                providerStatus = .unavailable(error.localizedDescription)
                logger.error("Remote display destruction failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func startMediaCapture() {
        guard let displayID = displayProvider.activeDisplayID else {
            mediaStatus = "Create the remote display before starting media capture."
            return
        }

        let width = max(1, CGDisplayPixelsWide(displayID))
        let height = max(1, CGDisplayPixelsHigh(displayID))
        let orientation: DisplayOrientation = width >= height ? .landscape : .portrait
        let configuration = VoidDisplayCaptureConfiguration(
            displayID: displayID,
            logicalSize: VoidDisplayCaptureDimensions(width: width, height: height),
            scaleFactor: 1,
            orientation: orientation,
            framesPerSecond: 60,
            capturesAudio: true
        )

        Task { @MainActor [weak self] in
            guard let self else { return }
            if let mediaCoordinator {
                await mediaCoordinator.stop()
            }

            let coordinator = VoidDisplayMediaCoordinator(configuration: configuration)
            let mediaSessionID = UUID()
            self.mediaSessionID = mediaSessionID
            coordinator.onOffer = { [weak self] offer in
                self?.mediaStatus = "WebRTC offer ready; send it through the paired control session."
                self?.logger.info("WebRTC offer created: \(offer.sdp.count, privacy: .public) SDP characters")
                self?.controlListener?.sendToPairedClients(
                    kind: .mediaOffer,
                    payload: MediaOfferPayload(
                        sessionID: mediaSessionID,
                        sdp: offer.sdp,
                        width: width,
                        height: height,
                        frameRate: 60
                    )
                )
            }
            coordinator.onICECandidate = { [weak self] candidate in
                self?.controlListener?.sendToPairedClients(
                    kind: .mediaICE,
                    payload: MediaICEPayload(
                        sessionID: mediaSessionID,
                        candidate: candidate.candidate,
                        sdpMid: candidate.sdpMid,
                        sdpMLineIndex: candidate.sdpMLineIndex
                    )
                )
            }
            mediaCoordinator = coordinator
            mediaStatus = coordinator.state.label
            await coordinator.start()
            mediaStatus = coordinator.state.label
        }
    }

    func stopMediaCapture() {
        Task { @MainActor [weak self] in
            guard let self, let mediaCoordinator else { return }
            await mediaCoordinator.stop()
            self.mediaCoordinator = nil
            mediaStatus = "Media stopped"
        }
    }

    func applyMediaAnswer(sdp: String) {
        guard let mediaCoordinator else {
            mediaStatus = "No active WebRTC media session is waiting for an answer."
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            await mediaCoordinator.applyRemoteAnswer(
                VoidDisplayWebRTCSessionDescription(type: .answer, sdp: sdp)
            )
            mediaStatus = mediaCoordinator.state.label
        }
    }

    private func applyMediaICE(_ payload: MediaICEPayload) {
        guard payload.sessionID == mediaSessionID,
              let index = payload.sdpMLineIndex,
              let mediaCoordinator else { return }
        Task { @MainActor in
            await mediaCoordinator.addRemoteICECandidate(
                VoidDisplayWebRTCICECandidate(
                    candidate: payload.candidate,
                    sdpMid: payload.sdpMid,
                    sdpMLineIndex: index
                )
            )
            mediaStatus = mediaCoordinator.state.label
        }
    }

    func setPairingApprovalEnabled(_ enabled: Bool) {
        pairingApproval.setEnabled(enabled)
        pairingStatus = enabled
            ? "New pairing requests will be accepted when the QR/code matches."
            : "Pairing is disabled. Existing paired devices remain trusted."
    }

    func rotatePairingCode() {
        guard let controlListener,
              let certificatePinning = try? tlsIdentityStore.load().certificatePinning else { return }
        controlListener.rotatePairingCode()
        pairingCode = controlListener.pairingCode
        pairingPayloadJSON = makePairingPayloadJSON(
            certificatePinning: certificatePinning,
            pairingCode: pairingCode,
            expiresAt: controlListener.pairingExpiresAt
        )
        pairingStatus = "Pairing code refreshed. It expires in 10 minutes."
    }

    func copyPairingPayload() {
        guard !pairingPayloadJSON.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pairingPayloadJSON, forType: .string)
        pairingStatus = "Pairing JSON copied. Paste it into the iPhone settings screen."
    }

    func copyPairingCode() {
        guard !pairingCode.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pairingCode, forType: .string)
        pairingStatus = "Pairing code copied."
    }

    private func sendCurrentDisplayState() {
        let display = displayProvider.activeDisplayDescriptor
        controlListener?.sendToPairedClients(
            kind: .displayState,
            payload: DisplayStatePayload(
                displays: display.map { [$0] } ?? [],
                selectedDisplayID: display?.id
            )
        )
    }

    private func makePairingPayloadJSON(
        certificatePinning: CertificatePinningMetadata,
        pairingCode: String,
        expiresAt: Date
    ) -> String {
        let endpointHost = pairingEndpointHost()
        let payload = PairingQRCodePayload(
            hostIdentity: DeviceIdentityMetadata(
                deviceID: hostID,
                deviceName: hostName,
                platform: .macOS,
                appVersion: "0.1.0"
            ),
            endpoint: "wss://" + endpointHost + ":" + String(LocalControlListener.controlPort.rawValue),
            pairingCode: pairingCode,
            certificatePinning: certificatePinning,
            expiresAt: expiresAt,
            nonce: UUID().uuidString
        )
        guard let data = try? MACLandJSON.makeEncoder().encode(payload) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginController.setEnabled(enabled)
    }

    func launchApplication(bundleIdentifier: String) {
        applicationCatalog.launch(bundleIdentifier: bundleIdentifier, activates: false) { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success:
                    self?.logger.info("Launched \(bundleIdentifier, privacy: .public)")
                    self?.refreshApplications()
                    if let apps = self?.appsListPayload() {
                        self?.controlListener?.sendToPairedClients(kind: .appsList, payload: apps)
                    }
                    self?.controlListener?.sendToPairedClients(
                        kind: .appLifecycle,
                        payload: AppLifecyclePayload(event: .launched, bundleIdentifier: bundleIdentifier)
                    )
                    await self?.placeLaunchedApplication(bundleIdentifier: bundleIdentifier)
                    self?.broadcastWindowsList()
                case let .failure(error):
                    self?.workspaceActionStatus = error.localizedDescription
                    self?.logger.error("Could not launch \(bundleIdentifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    private func focusApplication(bundleIdentifier: String) {
        do {
            guard let windowController else { throw ApplicationWindowError.noWindows(bundleIdentifier: bundleIdentifier) }
            let window = try windowController.locateWindows(for: bundleIdentifier).first
            guard let window else { throw ApplicationWindowError.noWindows(bundleIdentifier: bundleIdentifier) }
            try windowController.focus(window: window, in: bundleIdentifier)
            workspaceActionStatus = "Focused " + bundleIdentifier + "."
            broadcastWindowsList()
        } catch {
            workspaceActionStatus = error.localizedDescription
        }
    }

    private func closeApplication(bundleIdentifier: String) {
        do {
            guard let windowController else { throw ApplicationWindowError.noWindows(bundleIdentifier: bundleIdentifier) }
            for window in try windowController.locateWindows(for: bundleIdentifier) {
                try windowController.close(window: window, in: bundleIdentifier)
            }
            controlListener?.sendToPairedClients(
                kind: .appLifecycle,
                payload: AppLifecyclePayload(event: .terminated, bundleIdentifier: bundleIdentifier)
            )
            workspaceActionStatus = "Closed windows for " + bundleIdentifier + "."
            refreshApplications()
            controlListener?.sendToPairedClients(kind: .appsList, payload: appsListPayload())
            broadcastWindowsList()
        } catch {
            workspaceActionStatus = error.localizedDescription
        }
    }

    private func inject(batch: InputBatchPayload) {
        let origin = displayProvider.activeDisplayBounds?.origin ?? .zero
        do {
            for event in batch.events {
                var translated = event
                if let location = event.location {
                    translated.location = InputPoint(
                        x: location.x + origin.x,
                        y: location.y + origin.y
                    )
                }
                try inputInjector.inject(translated)
            }
        } catch {
            workspaceActionStatus = error.localizedDescription
        }
    }

    private func appsListPayload() -> AppsListPayload {
        AppsListPayload(
            applications: applications.map {
                ApplicationDescriptor(
                    bundleIdentifier: $0.bundleIdentifier,
                    name: $0.name,
                    isRunning: NSRunningApplication.runningApplications(withBundleIdentifier: $0.bundleIdentifier).contains { !$0.isTerminated },
                    processID: NSRunningApplication.runningApplications(withBundleIdentifier: $0.bundleIdentifier).first?.processIdentifier
                )
            }
        )
    }

    private func windowsListPayload() -> WindowsListPayload {
        guard let windowController else { return WindowsListPayload(windows: []) }
        let displayOrigin = displayProvider.activeDisplayBounds?.origin ?? .zero
        var descriptors: [RemoteWindowDescriptor] = []

        for application in applications {
            guard NSRunningApplication.runningApplications(
                withBundleIdentifier: application.bundleIdentifier
            ).contains(where: { !$0.isTerminated }) else { continue }

            guard let windows = try? windowController.locateWindows(
                for: application.bundleIdentifier
            ) else { continue }

            descriptors.append(contentsOf: windows.map { window in
                let remoteFrame = window.frame.map {
                    RemoteWindowFrame(
                        x: Double($0.origin.x - displayOrigin.x),
                        y: Double($0.origin.y - displayOrigin.y),
                        width: Double($0.width),
                        height: Double($0.height)
                    )
                }
                return RemoteWindowDescriptor(
                    id: window.id.description,
                    bundleIdentifier: application.bundleIdentifier,
                    applicationName: application.name,
                    title: window.title,
                    frame: remoteFrame,
                    isMinimized: window.isMinimized
                )
            })
        }
        return WindowsListPayload(windows: descriptors)
    }

    private func broadcastWindowsList() {
        controlListener?.sendToPairedClients(
            kind: .windowsList,
            payload: windowsListPayload()
        )
    }

    private func handleWindowCommand(_ command: WindowCommandPayload) {
        do {
            guard let windowController else {
                throw ApplicationWindowError.noWindows(bundleIdentifier: command.bundleIdentifier)
            }
            let windows = try windowController.locateWindows(for: command.bundleIdentifier)
            guard let window = windows.first(where: { $0.id.description == command.windowID }) else {
                throw ApplicationWindowError.noWindows(bundleIdentifier: command.bundleIdentifier)
            }
            switch command.action {
            case .focus:
                try windowController.focus(window: window, in: command.bundleIdentifier)
            case .minimize:
                try windowController.minimize(window: window, in: command.bundleIdentifier)
            case .restore:
                try windowController.restore(window: window, in: command.bundleIdentifier)
                try windowController.focus(window: window, in: command.bundleIdentifier)
            case .close:
                try windowController.close(window: window, in: command.bundleIdentifier)
            }
            workspaceActionStatus = "Updated " + command.bundleIdentifier + " window."
            broadcastWindowsList()
        } catch {
            workspaceActionStatus = error.localizedDescription
        }
    }

    func setTerminalControlEnabled(_ enabled: Bool) {
        terminalControlEnabled = enabled
        configureWindowController()
        workspaceActionStatus = enabled
            ? "Terminal window control enabled. Only use it on a trusted session."
            : "Terminal window control disabled."
    }

    private func configureWindowController() {
        guard let bounds = displayProvider.activeDisplayBounds else {
            windowController = nil
            return
        }
        windowController = try? ApplicationWindowController(
            displayBounds: bounds,
            policy: ApplicationWindowPolicy(allowsTerminalApplications: terminalControlEnabled)
        )
    }

    private func placeLaunchedApplication(bundleIdentifier: String) async {
        // AppKit may report the process before its first window exists.
        for _ in 0..<10 {
            guard let windowController else {
                workspaceActionStatus = "Create the remote display before launching applications."
                return
            }
            do {
                let windows = try windowController.locateWindows(for: bundleIdentifier)
                for window in windows {
                    _ = try windowController.place(window: window, in: bundleIdentifier)
                }
                workspaceActionStatus = "Placed \(bundleIdentifier) on the remote display."
                return
            } catch {
                workspaceActionStatus = error.localizedDescription
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private static var defaultHostName: String {
        Host.current().localizedName ?? "Mac"
    }

    private func pairingEndpointHost() -> String {
        let baseName = hostNetworkName
            .lowercased()
            .replacingOccurrences(of: ".local", with: "")
        let scalars = baseName.unicodeScalars.map { scalar -> Character in
            if scalar.isASCII, scalar.value == 45 || scalar.value == 46 || scalar.value >= 48 && scalar.value <= 57 || scalar.value >= 97 && scalar.value <= 122 {
                return Character(String(scalar))
            }
            return "-"
        }
        let normalized = String(scalars)
            .split(separator: "-")
            .joined(separator: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return (normalized.isEmpty ? "macland-host" : normalized) + ".local"
    }
}
