import SwiftUI
#if os(iOS)
import UIKit
#endif

private enum HomeColors {
    static let canvas = Color(red: 0.025, green: 0.055, blue: 0.095)
    static let surface = Color(red: 0.12, green: 0.18, blue: 0.25)
    static let surfaceRaised = Color(white: 0.12)
    static let control = Color(white: 0.16)
    static let border = Color.white.opacity(0.12)
    static let primaryText = Color.white.opacity(0.95)
    static let secondaryText = Color.white.opacity(0.62)
    static let mutedText = Color.white.opacity(0.40)
    static let success = Color(red: 0.45, green: 0.75, blue: 0.52)
    static let warning = Color(red: 0.86, green: 0.66, blue: 0.32)
    static let danger = Color(red: 0.86, green: 0.42, blue: 0.38)
    static let accent = Color.cyan
}

@MainActor
struct MACLandHomeView: View {
    @ObservedObject var workspace: WorkspaceState

    @State private var showsConnection = false
    @State private var showsSettings = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.055, green: 0.10, blue: 0.17), HomeColors.canvas, Color(red: 0.02, green: 0.12, blue: 0.19)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    HStack {
                        (Text("MAC").foregroundColor(.white) + Text("Land").foregroundColor(.cyan))
                            .font(.system(size: 27, weight: .bold))
                        Spacer()
                        Button { showsSettings = true } label: {
                            Image(systemName: "gearshape").font(.system(size: 21))
                        }.accessibilityLabel("Settings")
                    }.padding(.vertical, 14)

                    Button { showsConnection.toggle() } label: {
                        HStack(spacing: 18) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(LinearGradient(colors: [.blue, .cyan, Color(red: 0.03, green: 0.2, blue: 0.5)], startPoint: .bottomLeading, endPoint: .topTrailing))
                                    .frame(width: 76, height: 49)
                                Image(systemName: "desktopcomputer").font(.system(size: 37, weight: .light))
                            }
                            VStack(alignment: .leading, spacing: 7) {
                                Text(hostName).font(.system(size: 17, weight: .medium))
                                HStack(spacing: 6) {
                                    Circle().fill(workspace.connectionState.statusColor).frame(width: 10, height: 10)
                                    Text(workspace.connectionState.shortLabel).font(.system(size: 12))
                                }.foregroundStyle(HomeColors.secondaryText)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(HomeColors.secondaryText)
                        }.padding(20).frame(maxWidth: .infinity).modifier(HomeGlass())
                    }.buttonStyle(.plain)

                    VStack(spacing: 0) {
                        readinessRow("iPhone Paired", detail: workspace.connectionState.isConnected ? "This iPhone is connected" : "Connect this iPhone to your Mac", icon: "wifi", ready: workspace.connectionState.isConnected)
                        Divider().overlay(HomeColors.border).padding(.leading, 49)
                        readinessRow("Spatial Display", detail: workspace.mediaState.connectionState.label, icon: "display", ready: workspace.connectionState.isConnected)
                        Divider().overlay(HomeColors.border).padding(.leading, 49)
                        readinessRow("Input", detail: "Gaze + Optional Keyboard", icon: "square.3.layers.3d", ready: workspace.connectionState.isConnected)
                    }.padding(.horizontal, 20).padding(.vertical, 6).modifier(HomeGlass())

                    Button { workspace.isSpatialPresented = true } label: {
                        HStack(spacing: 15) {
                            Image(systemName: "vision.pro").font(.system(size: 29, weight: .light))
                            Text("Enter Spatial Workspace").font(.system(size: 16, weight: .semibold))
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.system(size: 13))
                        }.padding(.horizontal, 22).frame(height: 76)
                            .background(LinearGradient(colors: [Color(red: 0.02, green: 0.39, blue: 1), .cyan, Color(red: 0.04, green: 0.78, blue: 0.73)], startPoint: .leading, endPoint: .trailing), in: Capsule())
                            .overlay(Capsule().stroke(.white.opacity(0.35), lineWidth: 1))
                            .shadow(color: .cyan.opacity(0.27), radius: 20, y: 7)
                    }.buttonStyle(.plain).padding(.top, 3)

                    if showsConnection || !workspace.connectionState.isConnected {
                        ConnectionHub(workspace: workspace)
                    }
                    if workspace.connectionState.isConnected {
                        Button { workspace.isRemoteFullscreen = true } label: {
                            Label("Open Remote Display", systemImage: "display").font(.subheadline)
                        }.buttonStyle(.plain).padding(.top, 15).foregroundStyle(HomeColors.secondaryText)
                    }
                }.frame(maxWidth: 430).padding(.horizontal, 24).padding(.bottom, 30)
                    .frame(maxWidth: .infinity)
            }.scrollIndicators(.hidden)
        }.foregroundStyle(.white).preferredColorScheme(.dark)
            .sheet(isPresented: $showsSettings) { SettingsPlaceholderView(workspace: workspace).preferredColorScheme(.dark) }
#if os(iOS) && !SWIFT_PACKAGE
            .fullScreenCover(isPresented: $workspace.isSpatialPresented) { SpatialWorkspaceView(workspace: workspace) }
#endif
    }

    private var hostName: String {
        if case let .connected(name) = workspace.connectionState { return name }
        return "Your Mac"
    }

    private func readinessRow(_ title: String, detail: String, icon: String, ready: Bool) -> some View {
        HStack(spacing: 18) {
            Image(systemName: icon).font(.system(size: 21, weight: .regular)).frame(width: 27)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(HomeColors.secondaryText)
            }
            Spacer(minLength: 5)
            Circle().fill(ready ? Color.green : HomeColors.mutedText).frame(width: 8, height: 8)
        }.frame(minHeight: 57)
    }

}

@MainActor
private struct PhoneStatusBar: View {
    @ObservedObject var workspace: WorkspaceState

    var body: some View {
        HStack(spacing: 12) {
            Text("MACLand")
                .font(.headline)

            Spacer()

            Text(workspace.connectionState.shortLabel)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(workspace.connectionState.statusColor)

            statusActionButton
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(Color(white: 0.09))
        .overlay(alignment: .bottom) {
            Divider().overlay(HomeColors.border)
        }
    }

    @ViewBuilder
    private var statusActionButton: some View {
        switch workspace.connectionState {
        case .disconnected:
            HomeActionButton(title: "Find Mac", systemImage: "antenna.radiowaves.left.and.right", style: .secondary) {
                workspace.beginPairing()
            }
        case .pairing, .connecting:
            HomeActionButton(title: "Cancel", systemImage: "xmark", style: .secondary) {
                workspace.disconnect()
            }
        case .connected:
            HomeActionButton(title: "Disconnect", systemImage: "power", style: .secondary) {
                workspace.disconnect()
            }
        }
    }
}

@MainActor
private struct ConnectionHub: View {
    @ObservedObject var workspace: WorkspaceState
    @State private var isManualPairingExpanded = false
    @State private var selectedHostDescription: String?
    @State private var selectedHostID: String?
    @State private var enteredCode = ""

    private var state: ConnectionState { workspace.connectionState }
    private var errorMessage: String? {
        workspace.connectionError ?? workspace.mediaState.failureMessage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "Connection",
                detail: "Choose your Mac and enter the code shown in its menu bar."
            )

            statusBlock

            if state.isScanningForHosts && workspace.discovery.hosts.isEmpty {
                scanningRow
            }

            if !workspace.discovery.hosts.isEmpty {
                discoveryList
            }

            if !state.isConnected {
                codePairing
                DisclosureGroup("Advanced pairing") { manualPairing.padding(.top, 10) }
                    .font(.caption).foregroundStyle(HomeColors.secondaryText)
            }
            if let discoveryError = workspace.discovery.lastError {
                Text(discoveryError).font(.caption).foregroundStyle(HomeColors.warning)
            }

            if let errorMessage {
                errorBlock(errorMessage)
            }

            actionRow
        }
        .padding(14)
        .background(HomeColors.surface)
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(HomeColors.border, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onAppear { if !state.isConnected { workspace.beginPairing() } }
    }

    private var statusBlock: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if state.isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .tint(HomeColors.primaryText)
                } else {
                    Image(systemName: state.systemImage)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(state.statusColor)
                }
            }
            .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(statusTitle)
                    .font(.headline)
                    .foregroundStyle(HomeColors.primaryText)
                Text(statusDetail)
                    .font(.subheadline)
                    .foregroundStyle(HomeColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    private var statusTitle: String {
        switch state {
        case .disconnected:
            return "No Mac connected"
        case let .pairing(code):
            return code.isEmpty ? "Looking for your Mac" : "Waiting for Mac approval"
        case .connecting:
            return "Connecting to your Mac"
        case let .connected(deviceName):
            return "Connected to \(deviceName)"
        }
    }

    private var statusDetail: String {
        switch state {
        case .disconnected:
            return "Start MACLand on your Mac, then scan for it here."
        case let .pairing(code):
            return "Select your Mac below and enter its six-digit pairing code."
        case .connecting:
            return "The Mac must approve this device over the secure channel."
        case .connected:
            return "The remote desktop is ready."
        }
    }

    private var scanningRow: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Scanning for MACLand hosts…")
                .font(.subheadline)
                .foregroundStyle(HomeColors.secondaryText)
        }
        .padding(.vertical, 2)
    }

    private var discoveryList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nearby Macs")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeColors.primaryText)

            ForEach(workspace.discovery.hosts) { host in
                HStack(spacing: 10) {
                    Image(systemName: "macbook")
                        .frame(width: 20)
                        .foregroundStyle(HomeColors.secondaryText)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(host.name)
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                        Text(host.endpointDescription)
                            .font(.caption)
                            .foregroundStyle(HomeColors.mutedText)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 6)

                    Button(selectedHost?.id == host.id ? "Selected" : "Select") {
                        selectedHostID = host.id
                    }
                    .buttonStyle(HomeButtonStyle(kind: .secondary))
                    .font(.caption.weight(.medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(HomeColors.surfaceRaised)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(HomeColors.border, lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var selectedHost: MACLandDiscoveredHost? {
        workspace.discovery.hosts.first { $0.id == selectedHostID }
            ?? (workspace.discovery.hosts.count == 1 ? workspace.discovery.hosts.first : nil)
    }

    private var codePairing: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let host = selectedHost {
                Text("Pair with " + host.name).font(.subheadline.weight(.medium))
            } else {
                Text("Select a nearby Mac to connect").font(.subheadline)
            }
            TextField("Six-digit code from your Mac", text: $enteredCode)
                .textFieldStyle(.plain).font(.system(size: 19, weight: .medium, design: .monospaced))
                .padding(14).background(HomeColors.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
#if os(iOS)
                .keyboardType(.numberPad)
#endif
                .onChange(of: enteredCode) { _, value in
                    enteredCode = String(value.utf8.filter { $0 >= 48 && $0 <= 57 }.prefix(6).map { Character(UnicodeScalar($0)) })
                }
            HomeActionButton(title: state == .connecting ? "Connecting…" : "Connect to Mac", systemImage: "link", style: .primary) {
                if let host = selectedHost { workspace.connect(to: host, code: enteredCode) }
            }.disabled(selectedHost == nil || enteredCode.count != 6 || state == .connecting)
        }
    }

    private var manualPairing: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                isManualPairingExpanded.toggle()
            } label: {
                HStack {
                    Text(isManualPairingExpanded ? "Hide pairing data" : "Pair manually")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isManualPairingExpanded ? 90 : 0))
                        .font(.caption)
                        .foregroundStyle(HomeColors.mutedText)
                }
                .foregroundStyle(HomeColors.primaryText)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isManualPairingExpanded {
                if let selectedHostDescription {
                    Text("Pairing data from \(selectedHostDescription)")
                        .font(.caption)
                        .foregroundStyle(HomeColors.secondaryText)
                }

                TextField("Paste pairing data from the Mac", text: $workspace.pairingPayloadJSON, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.caption.monospaced())
                    .lineLimit(3...6)
                    .padding(10)
                    .background(HomeColors.canvas)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(HomeColors.border, lineWidth: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                HomeActionButton(title: "Connect with pairing data", systemImage: "link", style: .primary) {
                    workspace.connectFromPairingJSON()
                }
            }
        }
    }

    private func errorBlock(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(HomeColors.danger)

            VStack(alignment: .leading, spacing: 3) {
                Text("Connection problem")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HomeColors.primaryText)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(HomeColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color(red: 0.20, green: 0.10, blue: 0.10))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(HomeColors.danger.opacity(0.45), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            switch state {
            case .disconnected:
                if errorMessage == nil {
                    HomeActionButton(title: "Scan for Macs", systemImage: "antenna.radiowaves.left.and.right", style: .primary) {
                        workspace.beginPairing()
                    }
                } else {
                    HomeActionButton(title: "Retry", systemImage: "arrow.clockwise", style: .primary) {
                        workspace.reconnect()
                    }
                }
            case .pairing:
                HomeActionButton(title: "Cancel", systemImage: "xmark", style: .secondary) {
                    workspace.disconnect()
                }
                HomeActionButton(title: "Scan again", systemImage: "arrow.clockwise", style: .secondary) {
                    workspace.beginPairing()
                }
            case .connecting:
                HomeActionButton(title: "Cancel", systemImage: "xmark", style: .secondary) {
                    workspace.disconnect()
                }
            case .connected:
                HomeActionButton(title: "Open remote desktop", systemImage: "display", style: .primary) {
                    workspace.isRemoteFullscreen = true
                }
                HomeActionButton(title: "Disconnect", systemImage: "power", style: .danger) {
                    workspace.disconnect()
                }
            }
        }
    }
}

@MainActor
private struct DesktopSection: View {
    @ObservedObject var workspace: WorkspaceState

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Desktop",
                detail: "Open apps and keep the phone desktop ready."
            )

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(WorkspaceWindowKind.allCases) { kind in
                    AppTile(kind: kind, workspace: workspace)
                }
            }

            if !workspace.visibleWindows.isEmpty {
                VStack(spacing: 10) {
                    ForEach(workspace.visibleWindows) { window in
                        WindowFrame(window: window, workspace: workspace)
                    }
                }
            }
        }
    }
}

@MainActor
private struct AppTile: View {
    let kind: WorkspaceWindowKind
    @ObservedObject var workspace: WorkspaceState

    var body: some View {
        Button(action: open) {
            VStack(spacing: 8) {
                Image(systemName: kind.systemImage)
                    .font(.title3)
                Text(kind.title)
                    .font(.caption)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 76)
            .background(HomeColors.surfaceRaised)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(HomeColors.border, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(HomeColors.primaryText)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(kind.title)
    }

    private func open() {
        if kind == .remoteDisplay, workspace.connectionState.isConnected {
            workspace.isRemoteFullscreen = true
        } else {
            workspace.openWindow(kind)
        }
    }
}

@MainActor
private struct WindowFrame: View {
    let window: WorkspaceWindow
    @ObservedObject var workspace: WorkspaceState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: window.kind.systemImage)
                    .frame(width: 18)

                Text(window.title)
                    .font(.subheadline.weight(.semibold))

                if window.kind == .remoteDisplay {
                    Text(workspace.connectionState.shortLabel)
                        .font(.caption2)
                        .foregroundStyle(workspace.connectionState.statusColor)
                }

                Spacer()

                Button {
                    workspace.minimizeWindow(window.id)
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Minimize \(window.title)")

                Button {
                    workspace.closeWindow(window.id)
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close \(window.title)")
            }
            .foregroundStyle(HomeColors.primaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(white: 0.13))

            Group {
                switch window.kind {
                case .remoteDisplay:
                    RemoteDisplaySurface(
                        connectionState: workspace.connectionState,
                        mediaClient: workspace.mediaState.webRTCClient,
                        remoteSize: workspace.mediaState.displaySize,
                        onTouch: workspace.sendTouch,
                        onInput: workspace.sendDesktopInput,
                        onConnectionAction: {
                            if workspace.connectionState.isConnected {
                                workspace.isRemoteFullscreen = true
                            } else {
                                workspace.beginPairing()
                            }
                        }
                    )
                case .settings:
                    SettingsPlaceholderView(workspace: workspace)
                }
            }
            .frame(minHeight: 240)
        }
        .background(Color(white: 0.09))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    workspace.activeWindowID == window.id
                        ? HomeColors.border
                        : HomeColors.border.opacity(0.6),
                    lineWidth: 1
                )
        }
        .onTapGesture {
            workspace.focusWindow(window.id)
        }
    }
}

@MainActor
private struct DesktopDock: View {
    @ObservedObject var workspace: WorkspaceState

    var body: some View {
        HStack(spacing: 6) {
            DockButton(title: "Launcher", systemImage: "square.grid.2x2") {
                workspace.presentLauncher()
            }
            DockButton(title: "Remote", systemImage: "display") {
                if workspace.connectionState.isConnected {
                    workspace.isRemoteFullscreen = true
                } else {
                    workspace.openWindow(.remoteDisplay)
                }
            }
            DockButton(title: "Settings", systemImage: "gearshape") {
                workspace.openWindow(.settings)
            }
            DockButton(title: "Windows", systemImage: "rectangle.stack") {
                workspace.toggleTaskSwitcher()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(white: 0.09))
        .overlay(alignment: .top) {
            Divider().overlay(HomeColors.border)
        }
    }
}

@MainActor
private struct DockButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.body)
                Text(title)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 42)
            .foregroundStyle(HomeColors.primaryText)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

@MainActor
struct LauncherOverlay: View {
    @ObservedObject var workspace: WorkspaceState

    private var items: [WorkspaceWindowKind] {
        let query = workspace.launcherQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return WorkspaceWindowKind.allCases }
        return WorkspaceWindowKind.allCases.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        overlayPanel {
            HStack {
                Text("Launcher")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    workspace.dismissLauncher()
                }
                .buttonStyle(HomeButtonStyle(kind: .secondary))
            }

            TextField("Search apps", text: $workspace.launcherQuery)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(HomeColors.canvas)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(HomeColors.border, lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel("Search apps")

            if items.isEmpty {
                Text("No matching apps")
                    .foregroundStyle(HomeColors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(items) { kind in
                    Button {
                        workspace.openWindow(kind)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: kind.systemImage)
                                .frame(width: 24)
                            Text(kind.title)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .foregroundStyle(HomeColors.mutedText)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(HomeColors.primaryText)
                    .frame(minHeight: 42)
                }
            }
        }
    }

    @ViewBuilder
    private func overlayPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 14, content: content)
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: 420, alignment: .top)
            .background(Color(white: 0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(HomeColors.border, lineWidth: 1)
            }
            .padding(12)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .background(Color.black.opacity(0.55))
            .ignoresSafeArea()
    }
}

@MainActor
struct TaskSwitcherOverlay: View {
    @ObservedObject var workspace: WorkspaceState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Open Windows")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    workspace.toggleTaskSwitcher()
                }
                .buttonStyle(HomeButtonStyle(kind: .secondary))
            }

            if workspace.windows.isEmpty {
                Text("There are no open windows.")
                    .foregroundStyle(HomeColors.secondaryText)
            } else {
                ForEach(workspace.windows) { window in
                    Button {
                        workspace.focusWindow(window.id)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: window.kind.systemImage)
                                .frame(width: 24)
                            Text(window.title)
                            Spacer()
                            if window.id == workspace.activeWindowID {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(HomeColors.accent)
                            }
                        }
                        .foregroundStyle(HomeColors.primaryText)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: 42)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: 420, alignment: .top)
        .background(Color(white: 0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(HomeColors.border, lineWidth: 1)
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .background(Color.black.opacity(0.55))
        .ignoresSafeArea()
    }
}

@MainActor
struct RemoteSessionFullscreenView: View {
    @ObservedObject var workspace: WorkspaceState
    @State private var lastTouch: RemoteTouchPoint?
    @State private var trackpadMode = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geometry in
                ZStack {
                    if workspace.connectionState.isConnected {
                        LiveRemoteVideoSurface(client: workspace.mediaState.webRTCClient)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        sessionProgress
                    }
                }
                .contentShape(Rectangle())
                #if os(iOS)
                .overlay {
                    DesktopTouchSurface(remoteSize: workspace.mediaState.displaySize,
                                        trackpadMode: trackpadMode,
                                        enabled: workspace.connectionState.isConnected,
                                        send: workspace.sendDesktopInput)
                }
                #else
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    sendTouch(at: value.location, in: geometry.size)
                })
                #endif
            }
            .aspectRatio(remoteAspectRatio, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .overlay(alignment: .top) {
            VStack(spacing: 6) {
                sessionBar
                if let error = workspace.inputError {
                    Text(error).font(.caption).foregroundStyle(.white)
                        .padding(12).background(Color.orange.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 12)
                }
            }
        }
        .overlay(alignment: .bottom) {
            sessionFooter
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
#if os(iOS)
        .persistentSystemOverlays(.hidden)
#if !SWIFT_PACKAGE
        .fullScreenCover(isPresented: $workspace.isSpatialPresented) {
            SpatialWorkspaceView(workspace: workspace)
        }
#endif
#endif
    }

    private var remoteAspectRatio: CGFloat {
        guard workspace.mediaState.displaySize.width > 0,
              workspace.mediaState.displaySize.height > 0 else { return 9.0 / 19.5 }
        return workspace.mediaState.displaySize.width / workspace.mediaState.displaySize.height
    }

    private var sessionBar: some View {
        HStack(spacing: 10) {
            Button {
                workspace.isRemoteFullscreen = false
            } label: {
                Label("Home", systemImage: "house")
                    .font(.caption.weight(.semibold))
                    .frame(minHeight: 32)
            }
            .buttonStyle(HomeButtonStyle(kind: .secondary))

            Spacer()

#if os(iOS) && !SWIFT_PACKAGE
            Button { workspace.isSpatialPresented = true } label: {
                Image(systemName: "vision.pro")
            }
#endif
            Text(sessionStatus)
                .font(.caption)
                .foregroundStyle(HomeColors.secondaryText)
                .lineLimit(1)

            Spacer()

            Button {
                workspace.disconnect()
            } label: {
                Label("Disconnect", systemImage: "power")
                    .font(.caption.weight(.semibold))
                    .frame(minHeight: 32)
            }
            .buttonStyle(HomeButtonStyle(kind: .danger))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(white: 0.08))
        .overlay(alignment: .bottom) {
            Divider().overlay(HomeColors.border)
        }
    }

    private var sessionFooter: some View {
        HStack(spacing: 12) {
            Text("\(Int(workspace.mediaState.displaySize.width)) × \(Int(workspace.mediaState.displaySize.height))")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(HomeColors.secondaryText)

            Spacer()

            Button(trackpadMode ? "Trackpad" : "Direct") { trackpadMode.toggle() }
                .font(.caption.bold())
                .foregroundStyle(.cyan)

            if let lastTouch {
                Text("Touch \(Int(lastTouch.remote.x)) × \(Int(lastTouch.remote.y))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(HomeColors.secondaryText)
            } else {
                Text("Tap to click · Hold to drag")
                    .font(.caption2)
                    .foregroundStyle(HomeColors.mutedText)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color(white: 0.08))
        .overlay(alignment: .top) {
            Divider().overlay(HomeColors.border)
        }
    }

    private var sessionStatus: String {
        switch workspace.connectionState {
        case let .connected(deviceName):
            return "Connected to \(deviceName)"
        case .connecting:
            return workspace.mediaState.connectionState == .reconnecting
                ? "Reconnecting to Mac"
                : "Connecting to Mac"
        case .pairing:
            return "Pairing"
        case .disconnected:
            return "Connection ended"
        }
    }

    @ViewBuilder
    private var sessionProgress: some View {
        VStack(spacing: 12) {
            if workspace.connectionState.isBusy {
                ProgressView()
                    .tint(.white)
            }

            Text(sessionStatus)
                .font(.headline)

            Text(sessionDetail)
                .font(.subheadline)
                .foregroundStyle(HomeColors.secondaryText)
                .multilineTextAlignment(.center)

            if let errorMessage = workspace.connectionError ?? workspace.mediaState.failureMessage {
                HomeActionButton(title: "Reconnect", systemImage: "arrow.clockwise", style: .primary) {
                    workspace.reconnect()
                }
                .frame(maxWidth: 220)
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(HomeColors.danger)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
        .foregroundStyle(HomeColors.primaryText)
        .padding(24)
    }

    private var sessionDetail: String {
        switch workspace.connectionState {
        case .disconnected:
            return "The session ended. Reconnect or return to the phone desktop."
        case .connecting:
            return workspace.mediaState.connectionState == .reconnecting
                ? "Trying to restore the secure control channel."
                : "The Mac is approving this device and opening the media session."
        case .pairing:
            return "Waiting for the Mac to approve this device."
        case .connected:
            return ""
        }
    }

    private func sendTouch(at location: CGPoint, in size: CGSize) {
        guard workspace.connectionState.isConnected else { return }
        let mapper = RemoteDisplayCoordinateMapper(
            remoteSize: workspace.mediaState.displaySize,
            surfaceSize: size
        )
        guard let touch = mapper.map(location) else { return }
        lastTouch = touch
        workspace.sendTouch(touch)
    }
}

@MainActor
private struct RemoteDisplaySurface: View {
    let connectionState: ConnectionState
    @ObservedObject var mediaClient: NativeWebRTCClient
    let remoteSize: CGSize
    let onTouch: (RemoteTouchPoint) -> Void
    let onInput: ([InputEvent]) -> Void
    let onConnectionAction: () -> Void
    @State private var lastTouch: RemoteTouchPoint?

    var body: some View {
        GeometryReader { geometry in
            let mapper = RemoteDisplayCoordinateMapper(
                remoteSize: remoteSize,
                surfaceSize: geometry.size
            )

            ZStack {
                Color.black

                if connectionState.isConnected {
                    connectedSurface(mapper: mapper)
                } else {
                    connectionPrompt
                }
            }
            .contentShape(Rectangle())
            #if os(iOS)
            .overlay {
                if connectionState.isConnected {
                    DesktopTouchSurface(remoteSize: remoteSize, trackpadMode: false,
                                        enabled: true, send: onInput)
                }
            }
            #else
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard connectionState.isConnected else { return }
                        guard let touch = mapper.map(value.location) else { return }
                        lastTouch = touch
                        onTouch(touch)
                    }
            )
            #endif
        }
        .aspectRatio(remoteSize.width / remoteSize.height, contentMode: .fit)
        .clipped()
    }

    @ViewBuilder
    private func connectedSurface(mapper: RemoteDisplayCoordinateMapper) -> some View {
        ZStack(alignment: .bottomLeading) {
            LiveRemoteVideoSurface(client: mediaClient)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(connectionState.label) · video surface ready")
                    .font(.caption.weight(.semibold))
                if let lastTouch {
                    Text("Touch \(Int(lastTouch.remote.x)) × \(Int(lastTouch.remote.y))")
                        .font(.caption2.monospacedDigit())
                } else {
                    Text("Tap to click · Hold to drag · Two fingers to scroll")
                        .font(.caption2)
                }
            }
            .foregroundStyle(.white)
            .padding(10)
            .background(Color.black.opacity(0.65))
        }
    }

    @ViewBuilder
    private var connectionPrompt: some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.connected.to.line.below")
                .font(.largeTitle)
            Text(connectionState.surfaceTitle)
                .font(.headline)
            Text(connectionState.surfaceMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            switch connectionState {
            case .disconnected:
                Button("Pair a Mac", action: onConnectionAction)
                    .buttonStyle(HomeButtonStyle(kind: .primary))
            case let .pairing(code):
                if code.isEmpty {
                    Text("The host pairing transport is not available yet.")
                        .foregroundStyle(.secondary)
                } else {
                    Text(code)
                        .font(.title3.monospaced().weight(.semibold))
                        .foregroundStyle(.white)
                }
            case .connecting:
                ProgressView()
                    .tint(.white)
                Text("Waiting for secure host signaling…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .connected:
                EmptyView()
            }
        }
        .foregroundStyle(.white)
        .padding(20)
    }
}

@MainActor
private struct SettingsPlaceholderView: View {
    @ObservedObject var workspace: WorkspaceState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settings")
                .font(.headline)
            Text("Connection and display preferences will live here.")
                .foregroundStyle(HomeColors.secondaryText)

            TextField("Paste pairing JSON from the Mac", text: $workspace.pairingPayloadJSON, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.caption.monospaced())
                .lineLimit(3...8)
                .padding(10)
                .background(HomeColors.canvas)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(HomeColors.border, lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))

            HomeActionButton(title: "Connect from pairing data", systemImage: "link", style: .primary) {
                workspace.connectFromPairingJSON()
            }

            HStack {
                Text("Status")
                Spacer()
                Text(workspace.connectionState.label)
                    .foregroundStyle(HomeColors.secondaryText)
            }

            Divider().overlay(HomeColors.border)

            HomeActionButton(title: "Disconnect", systemImage: "power", style: .danger) {
                workspace.disconnect()
            }
            .disabled(!workspace.connectionState.isConnected)
            .opacity(workspace.connectionState.isConnected ? 1 : 0.5)

            Spacer()
        }
        .foregroundStyle(HomeColors.primaryText)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SectionHeader: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeColors.primaryText)
            Text(detail)
                .font(.caption)
                .foregroundStyle(HomeColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private enum HomeButtonKind {
    case primary
    case secondary
    case danger
}

private struct HomeActionButton: View {
    let title: String
    let systemImage: String
    let style: HomeButtonKind
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 38)
        }
        .buttonStyle(HomeButtonStyle(kind: style))
    }
}

private struct HomeButtonStyle: ButtonStyle {
    let kind: HomeButtonKind

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foregroundColor)
            .background(configuration.isPressed ? pressedColor : backgroundColor)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(borderColor, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.9 : 1)
    }

    private var foregroundColor: Color {
        switch kind {
        case .primary:
            return Color.black.opacity(0.88)
        case .secondary, .danger:
            return HomeColors.primaryText
        }
    }

    private var backgroundColor: Color {
        switch kind {
        case .primary:
            return HomeColors.accent
        case .secondary:
            return HomeColors.control
        case .danger:
            return Color(red: 0.30, green: 0.13, blue: 0.13)
        }
    }

    private var pressedColor: Color {
        switch kind {
        case .primary:
            return HomeColors.accent.opacity(0.82)
        case .secondary:
            return Color(white: 0.22)
        case .danger:
            return Color(red: 0.38, green: 0.16, blue: 0.16)
        }
    }

    private var borderColor: Color {
        switch kind {
        case .primary:
            return HomeColors.accent
        case .secondary:
            return HomeColors.border
        case .danger:
            return HomeColors.danger.opacity(0.55)
        }
    }
}

private extension ConnectionState {
    var shortLabel: String {
        switch self {
        case .disconnected:
            return "No Mac"
        case .pairing:
            return "Pairing"
        case .connecting:
            return "Connecting"
        case .connected:
            return "Connected"
        }
    }

    var statusColor: Color {
        switch self {
        case .disconnected:
            return HomeColors.mutedText
        case .pairing, .connecting:
            return HomeColors.warning
        case .connected:
            return HomeColors.success
        }
    }

    var systemImage: String {
        switch self {
        case .disconnected:
            return "rectangle.connected.to.line.below"
        case .pairing:
            return "magnifyingglass"
        case .connecting:
            return "arrow.triangle.2.circlepath"
        case .connected:
            return "checkmark.circle"
        }
    }

    var isBusy: Bool {
        switch self {
        case .pairing, .connecting:
            return true
        case .disconnected, .connected:
            return false
        }
    }

    var showsPairingEntry: Bool {
        switch self {
        case .disconnected, .pairing:
            return true
        case .connecting, .connected:
            return false
        }
    }

    var isScanningForHosts: Bool {
        if case .pairing(let code) = self {
            return code.isEmpty
        }
        return false
    }

    var surfaceTitle: String {
        switch self {
        case .disconnected:
            return "No Mac connected"
        case .pairing:
            return "Ready to pair"
        case .connecting:
            return "Connecting to Mac"
        case .connected:
            return "Media connected"
        }
    }

    var surfaceMessage: String {
        switch self {
        case .disconnected:
            return "Pair a Mac to start a remote display session."
        case .pairing:
            return "Enter the code shown on your Mac."
        case .connecting:
            return "Waiting for the media session to open."
        case .connected:
            return ""
        }
    }
}

private struct HomeGlass: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .background(Color(red: 0.10, green: 0.18, blue: 0.26).opacity(0.65), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.18), lineWidth: 0.75))
            .shadow(color: .black.opacity(0.2), radius: 14, y: 8)
    }
}

#if os(iOS)
/// A UIKit overlay keeps multi-touch gestures separate from the streamed video.
private struct DesktopTouchSurface: UIViewRepresentable {
    var remoteSize: CGSize
    var trackpadMode: Bool
    var enabled: Bool
    var send: ([InputEvent]) -> Void

    func makeUIView(context: Context) -> DesktopGestureView { DesktopGestureView() }
    func updateUIView(_ view: DesktopGestureView, context: Context) {
        if view.trackpadMode != trackpadMode || view.remoteSize != remoteSize || !enabled {
            view.releaseButton()
        }
        view.remoteSize = remoteSize
        view.trackpadMode = trackpadMode
        view.send = send
        view.isUserInteractionEnabled = enabled
    }
    static func dismantleUIView(_ view: DesktopGestureView, coordinator: ()) { view.releaseButton() }
}

@MainActor
private final class DesktopGestureView: UIView, UIGestureRecognizerDelegate {
    var remoteSize = CGSize.zero
    var trackpadMode = false
    var send: ([InputEvent]) -> Void = { _ in }
    private var cursor: CGPoint?
    private var dragging = false

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        isMultipleTouchEnabled = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(click(_:)))
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(click(_:)))
        doubleTap.numberOfTapsRequired = 2
        tap.require(toFail: doubleTap)
        let rightTap = UITapGestureRecognizer(target: self, action: #selector(click(_:)))
        rightTap.numberOfTouchesRequired = 2
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePointerPan(_:)))
        pan.maximumNumberOfTouches = 1
        let scroll = UIPanGestureRecognizer(target: self, action: #selector(scroll(_:)))
        scroll.minimumNumberOfTouches = 2
        scroll.maximumNumberOfTouches = 2
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(hold(_:)))
        hold.minimumPressDuration = 0.45
        hold.allowableMovement = 12
        for gesture in [tap, doubleTap, rightTap, pan, scroll, hold] {
            gesture.delegate = self
            addGestureRecognizer(gesture)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        (gestureRecognizer is UILongPressGestureRecognizer && otherGestureRecognizer is UIPanGestureRecognizer && otherGestureRecognizer.numberOfTouches <= 1)
        || (otherGestureRecognizer is UILongPressGestureRecognizer && gestureRecognizer is UIPanGestureRecognizer && gestureRecognizer.numberOfTouches <= 1)
    }

    private func point(at local: CGPoint) -> InputPoint? {
        guard remoteSize.width > 0, remoteSize.height > 0 else { return nil }
        if !trackpadMode {
            guard let mapped = RemoteDisplayCoordinateMapper(remoteSize: remoteSize, surfaceSize: bounds.size).map(local) else { return nil }
            cursor = mapped.remote
        } else if cursor == nil {
            cursor = CGPoint(x: remoteSize.width / 2, y: remoteSize.height / 2)
        }
        guard let cursor else { return nil }
        return InputPoint(x: Double(min(max(0, cursor.x), remoteSize.width - 1)),
                          y: Double(min(max(0, cursor.y), remoteSize.height - 1)))
    }
    private var timestamp: UInt64 { UInt64(Date().timeIntervalSince1970 * 1000) }

    @objc private func click(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended, let point = point(at: gesture.location(in: self)) else { return }
        let button: MouseButton = gesture.numberOfTouchesRequired == 2 ? .right : .left
        var events = [InputEvent(kind: .pointerMove, timestamp: timestamp, location: point)]
        for count in 1...gesture.numberOfTapsRequired {
            events.append(InputEvent(kind: .pointerButton, timestamp: timestamp, location: point,
                                     button: button, pressed: true, clickCount: count))
            events.append(InputEvent(kind: .pointerButton, timestamp: timestamp, location: point,
                                     button: button, pressed: false, clickCount: count))
        }
        send(events)
    }
    @objc private func handlePointerPan(_ gesture: UIPanGestureRecognizer) {
        if trackpadMode {
            _ = point(at: gesture.location(in: self))
            let delta = gesture.translation(in: self)
            let previous = cursor ?? .zero
            cursor = CGPoint(x: min(max(0, previous.x + delta.x * 1.5), remoteSize.width - 1),
                             y: min(max(0, previous.y + delta.y * 1.5), remoteSize.height - 1))
            gesture.setTranslation(.zero, in: self)
        }
        if let point = point(at: gesture.location(in: self)) {
            send([InputEvent(kind: .pointerMove, timestamp: timestamp, location: point,
                             button: dragging ? .left : nil, pressed: dragging)])
        }
        if gesture.state == .cancelled || gesture.state == .ended || gesture.state == .failed { releaseButton() }
    }
    @objc private func hold(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began, let point = point(at: gesture.location(in: self)) {
            dragging = true
            send([InputEvent(kind: .pointerMove, timestamp: timestamp, location: point),
                  InputEvent(kind: .pointerButton, timestamp: timestamp, location: point, button: .left, pressed: true)])
        } else if gesture.state == .changed, !trackpadMode, let point = point(at: gesture.location(in: self)) {
            send([InputEvent(kind: .pointerMove, timestamp: timestamp, location: point, button: .left, pressed: true)])
        } else if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed { releaseButton() }
    }
    @objc private func scroll(_ gesture: UIPanGestureRecognizer) {
        releaseButton()
        guard gesture.state == .changed, let point = point(at: gesture.location(in: self)) else { return }
        let delta = gesture.translation(in: self)
        gesture.setTranslation(.zero, in: self)
        send([InputEvent(kind: .scroll, timestamp: timestamp, location: point,
                         scrollDelta: InputPoint(x: Double(delta.x), y: Double(delta.y)))])
    }
    func releaseButton() {
        guard dragging else { return }
        dragging = false
        if let cursor {
            send([InputEvent(kind: .pointerButton, timestamp: timestamp,
                             location: InputPoint(x: Double(cursor.x), y: Double(cursor.y)), button: .left, pressed: false)])
        }
    }
}
#endif

@MainActor
private struct LiveRemoteVideoSurface: View {
    @ObservedObject var client: NativeWebRTCClient
    var body: some View {
        NativeWebRTCVideoSurface(videoTrack: client.remoteVideoTrack)
            .overlay {
                #if canImport(WebRTC) && !SWIFT_PACKAGE
                if !client.hasReceivedFrame {
                    VStack(spacing: 12) {
                        if client.connectionState != .failed { ProgressView().tint(.cyan) }
                        Text(client.failureMessage ?? "Waiting for Mac video…")
                            .font(.callout).multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.white).padding(24)
                    .background(Color.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
                    .allowsHitTesting(false)
                }
                #endif
            }
    }
}
