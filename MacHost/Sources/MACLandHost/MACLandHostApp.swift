import AppKit
import Combine
import SwiftUI

@main
struct MACLandHostApp: App {
    @NSApplicationDelegateAdaptor(MACLandStatusItemDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
private final class MACLandStatusItemDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var panelController: MACLandPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let runtime = HostRuntime()

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = MACLandMenuBarIcon.makeIcon()
            button.image?.isTemplate = true
            button.toolTip = "MACLand"
            button.action = #selector(togglePanel(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        self.statusItem = statusItem

        panelController = MACLandPanelController(runtime: runtime)
        panelController?.onStatusItemChanged = { [weak self] in
            self?.statusItem?.button?.image = MACLandMenuBarIcon.makeIcon()
            self?.statusItem?.button?.image?.isTemplate = true
        }
    }

    @objc private func togglePanel(_ sender: NSStatusBarButton) {
        guard let panelController else { return }
        if panelController.isVisible {
            panelController.close()
        } else {
            panelController.open(relativeTo: sender)
        }
    }
}

private enum MACLandMenuBarIcon {
    static func makeIcon() -> NSImage {
        guard let symbol = NSImage(
            systemSymbolName: "vision.pro",
            accessibilityDescription: "MACLand"
        ) else {
            return fallbackIcon()
        }

        let configured = symbol.withSymbolConfiguration(
            .init(pointSize: 15, weight: .semibold)
        ) ?? symbol
        let icon = NSImage(size: NSSize(width: 18, height: 18))
        icon.lockFocus()
        let bounds = NSRect(origin: .zero, size: icon.size)
        configured.draw(in: bounds)
        icon.unlockFocus()
        return icon
    }

    private static func fallbackIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()

        NSColor.white.setFill()
        let phone = NSBezierPath(roundedRect: NSRect(x: 5, y: 2.5, width: 8, height: 13), xRadius: 1.6, yRadius: 1.6)
        phone.fill()

        NSGraphicsContext.current?.compositingOperation = .copy
        NSColor.clear.setFill()
        let screen = NSBezierPath(roundedRect: NSRect(x: 5.8, y: 3.3, width: 6.4, height: 11), xRadius: 1, yRadius: 1)
        screen.fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver

        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: 8.4, y: 2.8, width: 1.2, height: 1)).fill()
        NSBezierPath(rect: NSRect(x: 8.2, y: 13.2, width: 1.6, height: 0.7)).fill()

        image.unlockFocus()
        return image
    }
}

@MainActor
private final class MACLandPanelController: NSObject {
    private struct MonitorToken: @unchecked Sendable {
        let value: Any
    }
    var onStatusItemChanged: (() -> Void)?

    private var window: NSPanel?
    private var eventMonitor: MonitorToken?

    var isVisible: Bool {
        window?.isVisible == true
    }

    init(runtime: HostRuntime) {
        super.init()

        let content = HostMenuView(
            runtime: runtime,
            onClose: { [weak self] in self?.close() },
            onStatusItemChanged: { [weak self] in self?.onStatusItemChanged?() }
        )

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 332, height: 510),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: content)
        self.window = panel

        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible else { return event }
            if event.keyCode == 53 {
                self.close()
                return nil
            }
            return event
        }
        eventMonitor = MonitorToken(value: monitor)
    }

    deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor.value)
        }
    }

    func open(relativeTo button: NSStatusBarButton) {
        guard let window, let screen = button.window?.screen ?? NSScreen.main else { return }

        let desiredWidth: CGFloat = 332
        let desiredHeight: CGFloat = 510
        let screenFrame = screen.visibleFrame
        let buttonFrame = button.window?.convertToScreen(button.convert(button.bounds, to: nil)) ?? button.window?.frame ?? .zero

        var origin = NSPoint(
            x: min(max(buttonFrame.midX - desiredWidth / 2, screenFrame.minX + 8), screenFrame.maxX - desiredWidth - 8),
            y: buttonFrame.minY - desiredHeight - 3
        )
        if origin.y < screenFrame.minY {
            origin.y = buttonFrame.maxY + 3
        }

        window.setFrame(NSRect(origin: origin, size: NSSize(width: desiredWidth, height: desiredHeight)), display: false)
        window.orderFrontRegardless()
    }

    func close() {
        guard let window else { return }
        window.orderOut(nil)
    }
}

private enum HostSection: String, CaseIterable, Identifiable {
    case host
    case pairing
    case media
    case apps
    case access
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .host: "Displays"
        case .pairing: "Pair iPhone"
        case .media: "Media"
        case .apps: "Apps"
        case .access: "Controls"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .host: "display"
        case .pairing: "qrcode"
        case .media: "speaker.wave.2"
        case .apps: "square.grid.2x2"
        case .access: "waveform.path"
        case .settings: "gearshape"
        }
    }
}

private enum MLColor {
    static let canvas = Color(red: 0.055, green: 0.12, blue: 0.20)
    static let surface = Color(red: 0.10, green: 0.19, blue: 0.27)
    static let raised = Color(red: 0.15, green: 0.25, blue: 0.34)
    static let line = Color.white.opacity(0.1)
    static let lineStrong = Color.white.opacity(0.2)
    static let text = Color.white.opacity(0.96)
    static let textSecondary = Color.white.opacity(0.66)
    static let textMuted = Color.white.opacity(0.45)
    static let green = Color(red: 0.42, green: 0.73, blue: 0.5)
    static let amber = Color(red: 0.86, green: 0.64, blue: 0.3)
    static let red = Color(red: 0.84, green: 0.36, blue: 0.33)
    static let blue = Color(red: 0.04, green: 0.55, blue: 0.95)
}

private struct HostMenuView: View {
    @ObservedObject var runtime: HostRuntime
    let onClose: () -> Void
    let onStatusItemChanged: () -> Void

    @State private var selectedSection: HostSection = .host
    @State private var showsDetail = false
    @State private var query = ""
    @State private var isCreatingDesktop = false
    @State private var isDestroyingDesktop = false
    @State private var isStartingMedia = false
    @State private var pendingPairingCode = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(MLColor.line).padding(.horizontal, 16)
            if showsDetail {
                HStack(spacing: 12) {
                    Button { showsDetail = false } label: {
                        Image(systemName: "chevron.left").font(.system(size: 15)).frame(width: 28, height: 34)
                    }.buttonStyle(.plain).accessibilityLabel("Back to MACLand menu")
                    Image(systemName: selectedSection.systemImage).font(.system(size: 23, weight: .light))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(selectedSection.title).font(.system(size: 16, weight: .semibold))
                        Text(sectionDetail).font(.system(size: 11)).foregroundStyle(MLColor.textSecondary)
                    }
                    Spacer(minLength: 0)
                }.foregroundStyle(MLColor.text).padding(.horizontal, 14).padding(.vertical, 12)
                ScrollView { content.padding(.horizontal, 16).padding(.bottom, 16) }
                footer
            } else {
                navRail
                Divider().overlay(MLColor.line).padding(.horizontal, 16)
                menuRow("iPhone", detail: runtime.pairingStatus, icon: "iphone", section: .pairing)
                menuRow("Permissions", detail: runtime.permissionSummary, icon: "shield.lefthalf.filled", section: .access)
                Button { selectedSection = .pairing; showsDetail = true } label: {
                    menuLabel("Show Pairing Code", detail: "Scan to connect a new iPhone", icon: "qrcode", chevron: false)
                }.buttonStyle(.plain)
                Spacer(minLength: 0)
            }
        }
        .frame(width: 332, height: 510)
        .background(.ultraThinMaterial)
        .background(LinearGradient(colors: [MLColor.surface, MLColor.canvas], startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.25), lineWidth: 0.75))
        .preferredColorScheme(.dark)
        .onAppear {
            if runtime.applications.isEmpty {
                runtime.refreshApplications()
            }
            pendingPairingCode = runtime.pairingCode
        }
        .onReceive(runtime.$pairingStatus) { _ in
            // Keep the status item refreshed after pairing or host actions.
            onStatusItemChanged()
        }
        .onReceive(runtime.$isRunning) { _ in
            onStatusItemChanged()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("MACLand").font(.system(size: 20, weight: .semibold))
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark").font(.system(size: 11)) }
                    .buttonStyle(.plain).foregroundStyle(MLColor.textSecondary).accessibilityLabel("Close MACLand panel")
            }
            HStack(spacing: 7) {
                Circle().fill(runtime.isRunning ? MLColor.green : MLColor.textMuted).frame(width: 10, height: 10)
                Text(runtime.hostName + (runtime.isRunning ? " · Host running" : " · Host stopped"))
                    .font(.system(size: 13)).foregroundStyle(MLColor.textSecondary).lineLimit(1)
            }
        }.padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 10)
    }

    private var navRail: some View {
        VStack(spacing: 0) {
            menuRow("Displays", detail: runtime.providerActionStatus.isEmpty ? "Remote display · Spatial Mode" : runtime.providerActionStatus, icon: "display", section: .host)
            menuRow("Media", detail: runtime.mediaStatus, icon: "speaker.wave.2", section: .media)
            menuRow("Apps", detail: "Launch and manage", icon: "square.grid.2x2", section: .apps)
            menuRow("Controls", detail: "Gaze, input and interaction", icon: "waveform.path", section: .access)
            menuRow("Settings", detail: "General, performance, updates", icon: "gearshape", section: .settings)
        }
    }

    private func menuRow(_ title: String, detail: String, icon: String, section: HostSection) -> some View {
        Button { selectedSection = section; showsDetail = true } label: {
            menuLabel(title, detail: detail, icon: icon)
        }.buttonStyle(.plain)
    }

    private func menuLabel(_ title: String, detail: String, icon: String, chevron: Bool = true) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon).font(.system(size: 24, weight: .light)).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(MLColor.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if chevron { Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(MLColor.textSecondary) }
        }.foregroundStyle(MLColor.text).padding(.horizontal, 18).frame(height: 51)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { Rectangle().fill(MLColor.line).frame(height: 0.5).padding(.leading, 62).padding(.trailing, 16) }
    }

    @ViewBuilder
    private var content: some View {
        switch selectedSection {
        case .host:
            hostPanel
        case .pairing:
            pairingPanel
        case .media:
            mediaPanel
        case .apps:
            appsPanel
        case .access:
            accessPanel
        case .settings:
            settingsPanel
        }
    }

    private var hostPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Host", detail: runtime.controlStatus)

            block {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 13) {
                        Image(systemName: "display").font(.system(size: 25, weight: .light)).foregroundStyle(MLColor.text)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(hostStateTitle)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(MLColor.text)
                            Text(hostStateDetail)
                                .font(.system(size: 11))
                                .foregroundStyle(MLColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 8)

                        if runtime.isBusy {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .padding(.bottom, 4)

                    Button(action: runtime.toggleHost) {
                        HStack(spacing: 8) {
                            if runtime.isBusy {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: runtime.isRunning ? "stop.fill" : "play.fill")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            Text(hostActionTitle)
                                .font(.system(size: 13, weight: .semibold))
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(LifecycleButtonStyle(running: runtime.isRunning))
                    .disabled(runtime.isBusy)
                    .accessibilityLabel(runtime.isRunning ? "Stop MACLand host" : "Start MACLand host")
                }
            }

            if runtime.isRunning {
                sectionLabel("Remote desktop", detail: runtime.displayStatus.label)

                block {
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(spacing: 8) {
                            ActionButton(
                                title: isCreatingDesktop ? "Creating…" : "Create desktop",
                                systemImage: "plus.rectangle",
                                action: createDesktop
                            )
                            ActionButton(
                                title: isDestroyingDesktop ? "Destroying…" : "Destroy",
                                systemImage: "trash",
                                action: destroyDesktop,
                                destructive: true
                            )
                        }
                        .disabled(isCreatingDesktop || isDestroyingDesktop)

                        Divider()
                            .overlay(MLColor.line)

                        statusRow("Provider", value: runtime.providerStatus.label, color: providerColor)
                        statusRow("Pairing", value: pairingValue, color: runtime.pairingCode.isEmpty ? MLColor.textMuted : MLColor.green)
                    }
                }
            }

            sectionLabel("Pairing", detail: runtime.pairingStatus)

            block {
                VStack(alignment: .leading, spacing: 10) {
                    if runtime.pairingPayloadJSON.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "qrcode")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(MLColor.textSecondary)
                            Text("Start the host to generate pairing data.")
                                .font(.system(size: 11))
                                .foregroundStyle(MLColor.textSecondary)
                        }
                    } else {
                        HStack(spacing: 13) {
                            Image(systemName: "qrcode").font(.system(size: 28, weight: .light)).foregroundStyle(MLColor.text)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Pairing code")
                                    .font(.system(size: 10))
                                    .foregroundStyle(MLColor.textMuted)
                                Text(runtime.pairingCode.isEmpty ? "------" : runtime.pairingCode)
                                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(MLColor.text)
                                    .textSelection(.enabled)
                            }

                            Spacer()

                            Button(action: runtime.copyPairingCode) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 12, weight: .medium))
                                    .frame(width: 30, height: 28)
                            }
                            .buttonStyle(SecondaryButtonStyle())
                            .help("Copy pairing code")
                            .accessibilityLabel("Copy pairing code")
                        }

                        VStack(spacing: 8) {
                            ActionButton(title: "Show data", systemImage: "doc.text.magnifyingglass", action: { pendingPairingCode = runtime.pairingCode })
                            ActionButton(title: "Copy data", systemImage: "doc.on.doc.fill", action: runtime.copyPairingPayload)
                        }
                    }
                }
            }

            if !pendingPairingCode.isEmpty {
                PairingDataView(runtime: runtime, onDismiss: { pendingPairingCode = "" })
            }
        }
    }

    private var pairingPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            block {
                VStack(spacing: 14) {
                    Image(systemName: "iphone.and.arrow.forward").font(.system(size: 34, weight: .light))
                    Text(runtime.pairingCode.isEmpty ? "Start the host to pair" : runtime.pairingCode)
                        .font(.system(size: runtime.pairingCode.isEmpty ? 17 : 36, weight: .semibold, design: .monospaced))
                        .textSelection(.enabled)
                    Text("On your iPhone, select this Mac and enter this code. Both devices must be on the same Wi-Fi.")
                        .font(.system(size: 12)).foregroundStyle(MLColor.textSecondary).multilineTextAlignment(.center)
                    if !runtime.isRunning {
                        ActionButton(title: "Start host", systemImage: "play.fill", action: runtime.start)
                    } else {
                        ActionButton(title: "Copy code", systemImage: "doc.on.doc", action: runtime.copyPairingCode)
                    }
                }.frame(maxWidth: .infinity).padding(.vertical, 8)
            }
        }
    }

    private var mediaPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Stream", detail: runtime.mediaStatus)

            block {
                VStack(alignment: .leading, spacing: 10) {
                    statusRow("Video", value: runtime.mediaStatus, color: mediaColor)
                    statusRow("Audio", value: "Capture available", color: MLColor.textSecondary)
                    statusRow("Microphone", value: "Off", color: MLColor.textSecondary)

                    Divider()
                        .overlay(MLColor.line)

                    VStack(spacing: 8) {
                        ActionButton(title: isStartingMedia ? "Starting…" : "Start stream", systemImage: "play.fill", action: startMedia)
                            .disabled(isStartingMedia)
                        ActionButton(title: "Stop stream", systemImage: "stop.fill", action: stopMedia)
                    }
                }
            }

            note("Video is available. Audio streaming is not available yet.")
        }
    }

    private var appsPanel: some View {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = runtime.applications.filter {
            trimmed.isEmpty || $0.name.localizedCaseInsensitiveContains(trimmed)
        }

        return VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Remote apps", detail: "Launch into the remote display")

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(MLColor.textSecondary)
                TextField("Search installed apps", text: $query).textFieldStyle(.plain)
                    .font(.system(size: 13)).foregroundStyle(MLColor.text)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).accessibilityLabel("Clear app search")
                }
            }.padding(12).modifier(MenuGlassCard())

            block {
                VStack(spacing: 0) {
                    if matches.isEmpty {
                        Text("No matching applications")
                            .font(.system(size: 11))
                            .foregroundStyle(MLColor.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 10)
                    } else {
                        ForEach(Array(matches.prefix(10))) { application in
                            AppRow(application: application, runtime: runtime)
                            if application.id != matches.prefix(10).last?.id {
                                Divider()
                                    .overlay(MLColor.line)
                            }
                        }
                    }
                }
            }

            HStack {
                Text("\(min(matches.count, 10)) of \(matches.count)")
                    .font(.system(size: 10))
                    .foregroundStyle(MLColor.textMuted)
                Spacer()
                Button {
                    runtime.refreshApplications()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(MLColor.textSecondary)
            }
        }
    }

    private var accessPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Access", detail: "Pairing and Terminal behavior")

            block {
                VStack(alignment: .leading, spacing: 13) {
                    Toggle(isOn: Binding(
                        get: { runtime.pairingApprovalEnabledForMenu },
                        set: runtime.setPairingApprovalEnabled
                    )) {
                        ToggleLabel(title: "Allow new pairings", detail: "Accept devices that have the current pairing code.")
                    }
                    .toggleStyle(.switch)
                    .tint(MLColor.green)

                    Toggle(isOn: Binding(
                        get: { runtime.terminalControlEnabledForMenu },
                        set: runtime.setTerminalControlEnabled
                    )) {
                        ToggleLabel(title: "Enable Terminal control", detail: "Window control for Terminal only after explicit approval.")
                    }
                    .toggleStyle(.switch)
                    .tint(MLColor.amber)
                }
            }

            sectionLabel("Permissions", detail: "Required host access")

            block {
                VStack(alignment: .leading, spacing: 10) {
                    statusRow("Screen recording", value: runtime.permissionCenter.state.screenRecording.rawValue, color: permissionColor(runtime.permissionCenter.state.screenRecording))
                    statusRow("Accessibility", value: runtime.permissionCenter.state.accessibility.rawValue, color: permissionColor(runtime.permissionCenter.state.accessibility))

                    Divider()
                        .overlay(MLColor.line)

                    Text(runtime.permissionSummary)
                        .font(.system(size: 10))
                        .foregroundStyle(MLColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true)

                    ActionButton(title: "Screen Recording Settings", systemImage: "record.circle", action: runtime.openPermissionSettings)
                    ActionButton(title: "Accessibility Settings", systemImage: "hand.point.up.left", action: runtime.permissionCenter.openAccessibilitySettings)
                }
            }
        }
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Host", detail: runtime.hostName)

            block {
                VStack(alignment: .leading, spacing: 10) {
                    statusRow("Control", value: runtime.controlStatus, color: runtime.isRunning ? MLColor.green : MLColor.textMuted)
                    statusRow("Provider", value: runtime.providerStatus.label, color: MLColor.textSecondary)
                    statusRow("Media", value: runtime.mediaStatus, color: MLColor.textSecondary)
                }
            }

            sectionLabel("Startup", detail: runtime.launchAtLoginController.statusMessage)

            block {
                Toggle(isOn: Binding(
                    get: { runtime.launchAtLoginController.isEnabled },
                    set: runtime.setLaunchAtLogin
                )) {
                    ToggleLabel(title: "Launch at login", detail: "Keep MACLand ready when you sign in.")
                }
                .toggleStyle(.switch)
                .tint(MLColor.green)
            }

            sectionLabel("Maintenance", detail: "Keep MACLand current")

            block {
                VStack(alignment: .leading, spacing: 10) {
                    statusRow("Pairing data", value: runtime.pairingPayloadJSON.isEmpty ? "No data yet" : "Available", color: runtime.pairingPayloadJSON.isEmpty ? MLColor.textMuted : MLColor.green)
                    ActionButton(title: "Refresh permissions", systemImage: "arrow.clockwise", action: runtime.refreshPermissions)
                    ActionButton(title: "Refresh display provider", systemImage: "display", action: runtime.refreshDisplayProvider)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                selectedSection = .access
            } label: {
                Label("Access", systemImage: "lock.shield")
                    .font(.system(size: 11, weight: .medium))
                    .frame(maxWidth: .infinity, minHeight: 28)
            }
            .buttonStyle(SecondaryButtonStyle())

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
                    .font(.system(size: 11, weight: .medium))
                    .frame(maxWidth: .infinity, minHeight: 28)
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityHint("Quits the MACLand host")
        }
        .padding(12)
        .background(MLColor.surface.opacity(0.3))
    }

    private var hostStateTitle: String {
        if runtime.isStarting {
            return "Preparing host"
        }
        if runtime.isStopping {
            return "Stopping host"
        }
        return runtime.isRunning ? "Host is running" : "Host is stopped"
    }

    private var hostStateDetail: String {
        if runtime.isStarting {
            return "Creating the remote desktop…"
        }
        if runtime.isStopping {
            return "Closing the remote desktop…"
        }
        if runtime.isRunning {
            return runtime.providerActionStatus.isEmpty ? runtime.controlStatus : runtime.providerActionStatus
        }
        if runtime.controlStatus != "Not running" {
            return runtime.controlStatus
        }
        return "Start the host to create and share the isolated Mac workspace."
    }

    private var hostActionTitle: String {
        if runtime.isStarting {
            return "Preparing desktop…"
        }
        if runtime.isStopping {
            return "Stopping host…"
        }
        return runtime.isRunning ? "Stop host" : "Start host"
    }

    private var pairingValue: String {
        if runtime.pairingCode.isEmpty {
            return "Not available"
        }
        return "Ready · " + runtime.pairingCode
    }

    private var mediaColor: Color {
        runtime.mediaStatus.localizedCaseInsensitiveContains("streaming")
            ? MLColor.green
            : MLColor.textSecondary
    }

    private var providerColor: Color {
        switch runtime.displayStatus {
        case .ready: MLColor.green
        case .experimentalPrivateAPI: MLColor.amber
        case .blockedPublicAPI, .unavailable: MLColor.red
        }
    }

    private func permissionColor(_ status: PermissionStatus) -> Color {
        switch status {
        case .granted: MLColor.green
        case .denied, .restricted: MLColor.red
        default: MLColor.amber
        }
    }

    private func createDesktop() {
        guard !isCreatingDesktop, !isDestroyingDesktop else { return }
        isCreatingDesktop = true
        runtime.createRemoteDisplay()
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            isCreatingDesktop = false
        }
    }

    private func destroyDesktop() {
        guard !isCreatingDesktop, !isDestroyingDesktop else { return }
        isDestroyingDesktop = true
        runtime.destroyRemoteDisplay()
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            isDestroyingDesktop = false
        }
    }

    private func startMedia() {
        guard !isStartingMedia else { return }
        isStartingMedia = true
        runtime.startMediaCapture()
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            isStartingMedia = false
        }
    }

    private func stopMedia() {
        runtime.stopMediaCapture()
    }

    private var sectionDetail: String {
        switch selectedSection {
        case .host: "Displays and device pairing"
        case .pairing: "Connect using a six-digit code"
        case .media: "Video, volume and audio"
        case .apps: "Launch and manage your Mac apps"
        case .access: "Input, pairing and permissions"
        case .settings: "General and maintenance"
        }
    }

    private func sectionLabel(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(MLColor.text)
            Text(detail).font(.system(size: 11)).foregroundStyle(MLColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }.padding(.horizontal, 3).padding(.top, 4)
    }

    private func block<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(14)
            .modifier(MenuGlassCard())
    }

    private func statusRow(_ title: String, value: String, color: Color) -> some View {
        HStack(spacing: 13) {
            Image(systemName: menuSymbol(title)).font(.system(size: 21, weight: .light))
                .foregroundStyle(MLColor.text).frame(width: 26)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(MLColor.text)
                Text(value).font(.system(size: 11)).foregroundStyle(MLColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 5)
            Circle().fill(color).frame(width: 7, height: 7)
        }.padding(.vertical, 4)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(MLColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 2)
    }
}

private struct PairingDataView: View {
    @ObservedObject var runtime: HostRuntime
    let onDismiss: () -> Void

    var body: some View {
        block {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Pairing data")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MLColor.text)
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(IconButtonStyle())
                    .accessibilityLabel("Dismiss pairing data")
                }

                Divider()
                    .overlay(MLColor.line)

                Text(runtime.pairingPayloadJSON.isEmpty ? "No pairing data generated yet." : runtime.pairingPayloadJSON)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(MLColor.textSecondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                ActionButton(title: "Copy pairing data", systemImage: "doc.on.doc", action: runtime.copyPairingPayload)
                    .disabled(runtime.pairingPayloadJSON.isEmpty)
            }
        }
    }

    private func block<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(14)
            .modifier(MenuGlassCard())
    }
}

private struct AppRow: View {
    let application: InstalledApplication
    @ObservedObject var runtime: HostRuntime

    var body: some View {
        Button { runtime.launchApplication(bundleIdentifier: application.bundleIdentifier) } label: {
            HStack(spacing: 13) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: application.url.path))
                    .resizable().frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 4) {
                    Text(application.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Text("Open in your workspace").font(.system(size: 11)).foregroundStyle(MLColor.textSecondary)
                }
                Spacer(minLength: 5)
                Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(MLColor.textSecondary)
            }.foregroundStyle(MLColor.text).frame(minHeight: 58).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .disabled(application.bundleIdentifier == "com.apple.Terminal" && !runtime.terminalControlEnabledForMenu)
            .accessibilityLabel("Launch \(application.name)")
    }
}

private struct StatusPill: View {
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(MLColor.textSecondary)
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(MLColor.raised)
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(MLColor.line, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel(title)
    }
}

private struct ToggleLabel: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: menuSymbol(title)).font(.system(size: 22, weight: .light)).frame(width: 26)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(MLColor.text)
                Text(detail).font(.system(size: 11)).foregroundStyle(MLColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.foregroundStyle(MLColor.text).padding(.vertical, 5)
    }
}

private struct ActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    var destructive = false

    private var detail: String {
        switch systemImage {
        case "arrow.clockwise": "Check current status"
        case "display": "Check your remote display"
        case "play.fill": "Share your Mac workspace"
        case "stop.fill": "End the current stream"
        case "plus.rectangle": "Add a remote workspace"
        case "trash": "Remove the remote display"
        case "doc.text.magnifyingglass": "View connection details"
        case "doc.on.doc.fill", "doc.on.doc": "Copy to clipboard"
        case "arrow.up.right.square": "Manage host permissions"
        default: ""
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage).font(.system(size: 21, weight: .light)).frame(width: 26)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 13, weight: .medium))
                    if !detail.isEmpty { Text(detail).font(.system(size: 10)).foregroundStyle(MLColor.textSecondary) }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(MLColor.textSecondary)
            }.padding(.horizontal, 12).padding(.vertical, 11).frame(maxWidth: .infinity, alignment: .leading)
        }.buttonStyle(SecondaryButtonStyle(destructive: destructive))
    }
}

private struct SecondaryButtonStyle: ButtonStyle {
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(destructive ? MLColor.red : MLColor.text)
            .background(configuration.isPressed ? MLColor.raised.opacity(0.7) : MLColor.raised.opacity(0.3))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(configuration.isPressed ? MLColor.lineStrong : MLColor.line, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(MLColor.textSecondary)
            .background(configuration.isPressed ? MLColor.raised : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct LifecycleButtonStyle: ButtonStyle {
    let running: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(MLColor.text)
            .background(
                configuration.isPressed
                    ? (running ? MLColor.raised : MLColor.blue.opacity(0.82))
                    : (running ? MLColor.raised : MLColor.blue)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(configuration.isPressed ? MLColor.lineStrong : MLColor.line, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct MenuGlassCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15))
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .fill(LinearGradient(colors: [.white.opacity(0.035), .cyan.opacity(0.035)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .allowsHitTesting(false)
            }
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.16), lineWidth: 0.75))
    }
}

private func menuSymbol(_ title: String) -> String {
    switch title {
    case "Video": "display"
    case "Audio": "speaker.wave.2"
    case "Microphone": "mic"
    case "Provider": "rectangle.on.rectangle"
    case "Pairing", "Pairing data", "Allow new pairings": "qrcode"
    case "Screen recording": "record.circle"
    case "Accessibility", "Control": "hand.point.up.left"
    case "Media": "play.rectangle"
    case "Enable Terminal control": "terminal"
    case "Launch at login": "power"
    default: "info.circle"
    }
}
