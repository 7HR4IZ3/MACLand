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
            systemSymbolName: "macbook.and.iphone",
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
    var onStatusItemChanged: (() -> Void)?

    private var window: NSPanel?
    private var eventMonitor: Any?

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
            contentRect: NSRect(x: 0, y: 0, width: 392, height: 600),
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

    }

    func open(relativeTo button: NSStatusBarButton) {
        if eventMonitor == nil {
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.isVisible else { return event }
                if event.keyCode == 53 {
                    self.close()
                    return nil
                }
                return event
            }
        }
        guard let window, let screen = button.window?.screen ?? NSScreen.main else { return }

        let desiredWidth: CGFloat = 392
        let desiredHeight: CGFloat = 600
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
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        guard let window else { return }
        window.orderOut(nil)
    }
}

private enum HostSection: String, CaseIterable, Identifiable {
    case host
    case media
    case apps
    case access
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .host: "Host"
        case .media: "Media"
        case .apps: "Apps"
        case .access: "Access"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .host: "dot.radiowaves.left.and.right"
        case .media: "waveform"
        case .apps: "square.grid.2x2"
        case .access: "lock.shield"
        case .settings: "gearshape"
        }
    }
}

private enum MLColor {
    static let canvas = Color(red: 0.07, green: 0.071, blue: 0.074)
    static let surface = Color(red: 0.1, green: 0.102, blue: 0.106)
    static let raised = Color(red: 0.135, green: 0.138, blue: 0.144)
    static let line = Color.white.opacity(0.1)
    static let lineStrong = Color.white.opacity(0.2)
    static let text = Color.white.opacity(0.96)
    static let textSecondary = Color.white.opacity(0.66)
    static let textMuted = Color.white.opacity(0.45)
    static let green = Color(red: 0.42, green: 0.73, blue: 0.5)
    static let amber = Color(red: 0.86, green: 0.64, blue: 0.3)
    static let red = Color(red: 0.84, green: 0.36, blue: 0.33)
    static let blue = Color(red: 0.48, green: 0.64, blue: 0.86)
}

private struct HostMenuView: View {
    @ObservedObject var runtime: HostRuntime
    let onClose: () -> Void
    let onStatusItemChanged: () -> Void

    @State private var selectedSection: HostSection = .host
    @State private var query = ""
    @State private var isCreatingDesktop = false
    @State private var isDestroyingDesktop = false
    @State private var isStartingMedia = false
    @State private var pendingPairingCode = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            navRail
            Divider()
                .overlay(MLColor.line)
            ScrollView {
                content
                    .padding(12)
            }
            footer
        }
        .frame(width: 392, height: 600)
        .background(MLColor.canvas)
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
        HStack(spacing: 10) {
            Image(systemName: "macbook.and.iphone")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MLColor.blue)

            VStack(alignment: .leading, spacing: 1) {
                Text("MACLand")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MLColor.text)
                Text(runtime.hostName)
                    .font(.system(size: 10))
                    .foregroundStyle(MLColor.textMuted)
                    .lineLimit(1)
            }

            Spacer()

            StatusPill(
                title: runtime.isRunning ? "Live" : "Off",
                color: runtime.isRunning ? MLColor.green : MLColor.textMuted
            )

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(IconButtonStyle())
            .help("Close")
            .accessibilityLabel("Close MACLand panel")
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(MLColor.surface)
    }

    private var navRail: some View {
        HStack(spacing: 6) {
            ForEach(HostSection.allCases) { section in
                Button {
                    selectedSection = section
                } label: {
                    Label(section.title, systemImage: section.systemImage)
                        .font(.system(size: 11, weight: selectedSection == section ? .semibold : .regular))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .foregroundStyle(selectedSection == section ? MLColor.text : MLColor.textSecondary)
                        .background(selectedSection == section ? MLColor.raised : .clear)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(selectedSection == section ? MLColor.lineStrong : MLColor.line, lineWidth: 1)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help(section.title)
                .accessibilityLabel(section.title)
                .accessibilityAddTraits(selectedSection == section ? .isSelected : [])
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(MLColor.surface)
    }

    @ViewBuilder
    private var content: some View {
        switch selectedSection {
        case .host:
            hostPanel
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
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
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
                                .font(.system(size: 12, weight: .semibold))
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, minHeight: 34)
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
                        HStack(spacing: 8) {
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
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
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

                        HStack(spacing: 8) {
                            ActionButton(title: "Show data", systemImage: "doc.text.magnifyingglass", action: { pendingPairingCode = runtime.pairingCode })
                            ActionButton(title: "Copy data", systemImage: "doc.on.doc.fill", action: runtime.copyPairingPayload)
                            ActionButton(title: "New code", systemImage: "arrow.clockwise", action: runtime.rotatePairingCode)
                        }
                    }
                }
            }

            if !pendingPairingCode.isEmpty {
                PairingDataView(runtime: runtime, onDismiss: { pendingPairingCode = "" })
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

                    HStack(spacing: 8) {
                        ActionButton(title: isStartingMedia ? "Starting…" : "Start stream", systemImage: "play.fill", action: startMedia)
                            .disabled(isStartingMedia)
                        ActionButton(title: "Stop stream", systemImage: "stop.fill", action: stopMedia)
                    }
                }
            }

            note("System audio capture is wired for the media milestone. WebRTC audio publishing still needs device validation.")
        }
    }

    private var appsPanel: some View {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = runtime.applications.filter {
            trimmed.isEmpty || $0.name.localizedCaseInsensitiveContains(trimmed)
        }

        return VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Remote apps", detail: "Launch into the remote display")

            TextField("Search installed apps", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(MLColor.text)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(MLColor.raised)
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(MLColor.line, lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))

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

                    ActionButton(title: "Open System Settings", systemImage: "arrow.up.right.square", action: runtime.openPermissionSettings)
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
                    HStack {
                        Image(systemName: "power")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(MLColor.textSecondary)
                        Text("Launch at login")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(MLColor.text)
                    }
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
        .background(MLColor.surface)
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

    private func sectionLabel(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MLColor.text)
            Spacer()
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(MLColor.textMuted)
                .lineLimit(1)
        }
    }

    private func block<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(11)
            .background(MLColor.surface)
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(MLColor.line, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private func statusRow(_ title: String, value: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(MLColor.textSecondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(color)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
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
            .padding(11)
            .background(MLColor.surface)
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(MLColor.line, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

private struct AppRow: View {
    let application: InstalledApplication
    @ObservedObject var runtime: HostRuntime

    var body: some View {
        HStack(spacing: 9) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: application.url.path))
                .resizable()
                .frame(width: 24, height: 24)

            Text(application.name)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)

            Spacer(minLength: 6)

            Button("Launch") {
                runtime.launchApplication(bundleIdentifier: application.bundleIdentifier)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(MLColor.textSecondary)
            .disabled(application.bundleIdentifier == "com.apple.Terminal" && !runtime.terminalControlEnabledForMenu)
            .accessibilityLabel("Launch \(application.name)")
        }
        .frame(minHeight: 36)
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
            RoundedRectangle(cornerRadius: 6)
                .stroke(MLColor.line, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityLabel(title)
    }
}

private struct ToggleLabel: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MLColor.text)
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(MLColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    var destructive = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 28)
        }
        .buttonStyle(SecondaryButtonStyle(destructive: destructive))
    }
}

private struct SecondaryButtonStyle: ButtonStyle {
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(destructive ? MLColor.red : MLColor.text)
            .background(configuration.isPressed ? MLColor.raised : MLColor.raised.opacity(0.62))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(configuration.isPressed ? MLColor.lineStrong : MLColor.line, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(MLColor.textSecondary)
            .background(configuration.isPressed ? MLColor.raised : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct LifecycleButtonStyle: ButtonStyle {
    let running: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(MLColor.text)
            .background(
                configuration.isPressed
                    ? (running ? MLColor.raised : MLColor.green.opacity(0.82))
                    : (running ? MLColor.raised : MLColor.green)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(configuration.isPressed ? MLColor.lineStrong : MLColor.line, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
