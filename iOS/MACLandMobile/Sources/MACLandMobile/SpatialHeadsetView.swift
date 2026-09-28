import Combine
import Foundation
import SwiftUI

#if os(iOS)
@preconcurrency import CoreMotion
import UIKit
#endif

public enum SpatialEnvironment: String, CaseIterable, Identifiable, Sendable {
    case dusk
    case midnight
    case horizon

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .dusk: "Dusk"
        case .midnight: "Midnight"
        case .horizon: "Horizon"
        }
    }
}

@MainActor
public final class SpatialSceneState: ObservableObject {
    @Published public var panelYaw: Double { didSet { persist() } }
    @Published public var panelPitch: Double { didSet { persist() } }
    @Published public var panelScale: Double { didSet { persist() } }
    @Published public var eyeSeparation: Double { didSet { persist() } }
    @Published public var vignetteStrength: Double { didSet { persist() } }
    @Published public var lensCorrectionEnabled: Bool { didSet { persist() } }
    @Published public var lensCorrectionStrength: Double { didSet { persist() } }
    @Published public var chromaticCorrection: Double { didSet { persist() } }
    @Published public var dwellEnabled: Bool { didSet { persist() } }
    @Published public var dwellDuration: Double { didSet { persist() } }
    @Published public var environment: SpatialEnvironment { didSet { persist() } }

    @Published public var isLauncherPresented = false
    @Published public var isWindowSwitcherPresented = false
    @Published public var isControlCenterPresented = false

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        panelYaw = defaults.object(forKey: "macland.spatial.panelYaw") as? Double ?? 0
        panelPitch = defaults.object(forKey: "macland.spatial.panelPitch") as? Double ?? 0
        panelScale = defaults.object(forKey: "macland.spatial.panelScale") as? Double ?? 0.86
        eyeSeparation = defaults.object(forKey: "macland.spatial.eyeSeparation") as? Double ?? 7
        vignetteStrength = defaults.object(forKey: "macland.spatial.vignette") as? Double ?? 0.28
        lensCorrectionEnabled = defaults.object(forKey: "macland.spatial.lensCorrectionEnabled") as? Bool ?? true
        lensCorrectionStrength = defaults.object(forKey: "macland.spatial.lensCorrectionStrength") as? Double ?? 0.18
        chromaticCorrection = defaults.object(forKey: "macland.spatial.chromaticCorrection") as? Double ?? 0.0025
        dwellEnabled = defaults.object(forKey: "macland.spatial.dwellEnabled") as? Bool ?? false
        dwellDuration = defaults.object(forKey: "macland.spatial.dwellDuration") as? Double ?? 1.2
        environment = SpatialEnvironment(
            rawValue: defaults.string(forKey: "macland.spatial.environment") ?? "dusk"
        ) ?? .dusk
    }

    public func resetPanel() {
        panelYaw = 0
        panelPitch = 0
        panelScale = 0.86
    }

    public func dismissOverlays() {
        isLauncherPresented = false
        isWindowSwitcherPresented = false
        isControlCenterPresented = false
    }

    public func showLauncher() {
        let next = !isLauncherPresented
        dismissOverlays()
        isLauncherPresented = next
    }

    public func showWindows() {
        let next = !isWindowSwitcherPresented
        dismissOverlays()
        isWindowSwitcherPresented = next
    }

    public func showControls() {
        let next = !isControlCenterPresented
        dismissOverlays()
        isControlCenterPresented = next
    }

    private func persist() {
        defaults.set(panelYaw, forKey: "macland.spatial.panelYaw")
        defaults.set(panelPitch, forKey: "macland.spatial.panelPitch")
        defaults.set(panelScale, forKey: "macland.spatial.panelScale")
        defaults.set(eyeSeparation, forKey: "macland.spatial.eyeSeparation")
        defaults.set(vignetteStrength, forKey: "macland.spatial.vignette")
        defaults.set(lensCorrectionEnabled, forKey: "macland.spatial.lensCorrectionEnabled")
        defaults.set(lensCorrectionStrength, forKey: "macland.spatial.lensCorrectionStrength")
        defaults.set(chromaticCorrection, forKey: "macland.spatial.chromaticCorrection")
        defaults.set(dwellEnabled, forKey: "macland.spatial.dwellEnabled")
        defaults.set(dwellDuration, forKey: "macland.spatial.dwellDuration")
        defaults.set(environment.rawValue, forKey: "macland.spatial.environment")
    }
}

@MainActor
struct SpatialHeadsetView: View {
    @ObservedObject var workspace: WorkspaceState
    @ObservedObject var mediaClient: NativeWebRTCClient
    @ObservedObject var scene: SpatialSceneState
    let onExit: () -> Void

    @StateObject private var pose = SpatialHeadPoseTracker()
    @State private var dwellProgress = 0.0
    @State private var previousYaw = 0.0
    @State private var previousPitch = 0.0
    @State private var dwellCooldownUntil = Date.distantPast
    @State private var overlayAnchorYaw = 0.0
    @State private var overlayAnchorPitch = 0.0
    @State private var previousGazeTarget: SpatialGazeTarget?

    private let gazeTimer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                eyeView(size: CGSize(width: geometry.size.width / 2, height: geometry.size.height), eye: -1)
                eyeView(size: CGSize(width: geometry.size.width / 2, height: geometry.size.height), eye: 1)
            }
            .background(Color.black)
            .onReceive(gazeTimer) { _ in
                updateDwell(size: CGSize(width: geometry.size.width / 2, height: geometry.size.height))
            }
        }
        .onAppear {
            HeadsetDeviceSession.begin()
            pose.start()
            workspace.refreshRemoteWindows()
        }
        .onDisappear {
            pose.stop()
            HeadsetDeviceSession.end()
        }
    }

    private func eyeView(size: CGSize, eye: Double) -> some View {
        ZStack {
            SpatialEnvironmentView(environment: scene.environment, headYaw: pose.yaw)

            remotePanel(size: size, eye: eye)

            if scene.isLauncherPresented {
                launcherPanel(size: size)
            } else if scene.isWindowSwitcherPresented {
                windowsPanel(size: size)
            } else if scene.isControlCenterPresented {
                controlsPanel(size: size)
            }

            reticle(size: size)
            spatialDock(size: size)

            RadialGradient(
                colors: [.clear, .black.opacity(scene.vignetteStrength)],
                center: .center,
                startRadius: min(size.width, size.height) * 0.26,
                endRadius: max(size.width, size.height) * 0.68
            )
            .allowsHitTesting(false)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .modifier(
            CardboardLensCorrection(
                enabled: scene.lensCorrectionEnabled,
                strength: scene.lensCorrectionStrength,
                chromaticCorrection: scene.chromaticCorrection,
                size: size
            )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            performGazeAction(size: size)
        }
    }

    private func remotePanel(size: CGSize, eye: Double) -> some View {
        let width = size.width * 0.84
        let height = min(size.height * 0.63, width / CGFloat(remoteAspectRatio))
        let relativeYaw = CGFloat(scene.panelYaw - pose.yaw)
        let relativePitch = CGFloat(scene.panelPitch - pose.pitch)
        let x = relativeYaw * size.width * 0.92 + CGFloat(eye * scene.eyeSeparation / 2)
        let y = -relativePitch * size.height * 0.9

        return VStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(.white.opacity(0.34)).frame(width: 4, height: 4)
                Text(activeWindowTitle)
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Text(workspace.connectionState.isConnected ? "LIVE" : "WAIT")
                    .font(.system(size: 7, weight: .bold, design: .rounded))
                    .foregroundStyle(workspace.connectionState.isConnected ? .green : .orange)
            }
            .foregroundStyle(.white.opacity(0.82))
            .padding(.horizontal, 10)
            .frame(height: 22)
            .background(.ultraThinMaterial)

            NativeWebRTCVideoSurface(videoTrack: mediaClient.remoteVideoTrack)
                .background(Color(white: 0.025))
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(.white.opacity(0.28), lineWidth: 0.7)
        }
        .shadow(color: .black.opacity(0.52), radius: 22, y: 13)
        .scaleEffect(CGFloat(scene.panelScale))
        .rotation3DEffect(
            .degrees(Double(relativeYaw) * 18),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.72
        )
        .offset(x: x, y: y)
        .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.86), value: scene.panelScale)
    }

    private func reticle(size: CGSize) -> some View {
        VStack(spacing: 4) {
            ZStack {
            Circle()
                .stroke(.black.opacity(0.5), lineWidth: 3)
                .frame(width: 18, height: 18)
            Circle()
                .stroke(.white.opacity(0.95), lineWidth: 1.3)
                .frame(width: 15, height: 15)
            if scene.dwellEnabled && dwellProgress > 0 {
                Circle()
                    .trim(from: 0, to: dwellProgress)
                    .stroke(.cyan, style: StrokeStyle(lineWidth: 2.3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 23, height: 23)
            }
            Circle().fill(.white).frame(width: 2.5, height: 2.5)
            }

            if let target = gazeTarget(size: size), target != .desktop {
                Text(target.label)
                    .font(.system(size: 6.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.58), in: Capsule())
            }
        }
        .allowsHitTesting(false)
    }

    private func spatialDock(size: CGSize) -> some View {
        let offset = projectedOffset(yaw: scene.panelYaw, pitch: scene.panelPitch - 0.35, size: size)
        return HStack(spacing: 5) {
                dockButton("Apps", icon: "circle.grid.3x3.fill") { presentOverlay(.launcher) }
                dockButton("Windows", icon: "rectangle.on.rectangle") {
                    workspace.refreshRemoteWindows()
                    presentOverlay(.windows)
                }
                dockButton("Center", icon: "scope") {
                    pose.recenter()
                    scene.resetPanel()
                }
                dockButton("Display", icon: "slider.horizontal.3") { presentOverlay(.controls) }
                dockButton("Exit", icon: "xmark") {
                    pose.stop()
                    onExit()
                }
            }
            .padding(5)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.2), lineWidth: 0.6))
            .offset(offset)
    }

    private func dockButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                Text(title).font(.system(size: 6.5, weight: .medium))
            }
            .foregroundStyle(.white)
            .frame(width: 37, height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func launcherPanel(size: CGSize) -> some View {
        spatialOverlay(size: size, title: "Applications", icon: "circle.grid.3x3.fill") {
            if workspace.applications.isEmpty {
                Text("No Mac applications found")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                        ForEach(workspace.applications, id: \.bundleIdentifier) { app in
                            Button {
                                workspace.launchApplication(app)
                                scene.dismissOverlays()
                            } label: {
                                VStack(spacing: 5) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(appTint(app.bundleIdentifier).gradient)
                                            .frame(width: 34, height: 34)
                                        Text(String(app.name.prefix(1)).uppercased())
                                            .font(.system(size: 15, weight: .bold, design: .rounded))
                                            .foregroundStyle(.white)
                                    }
                                    Text(app.name)
                                        .font(.system(size: 7.5, weight: .medium))
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func windowsPanel(size: CGSize) -> some View {
        spatialOverlay(size: size, title: "Mac Windows", icon: "rectangle.on.rectangle") {
            if workspace.remoteWindows.isEmpty {
                VStack(spacing: 7) {
                    Text("No controllable windows")
                        .font(.caption2.weight(.semibold))
                    Text("Accessibility permission is required on the Mac.")
                        .font(.system(size: 7.5))
                        .foregroundStyle(.secondary)
                    Button("Refresh") { workspace.refreshRemoteWindows() }
                        .font(.caption2)
                        .buttonStyle(.bordered)
                }
            } else {
                ScrollView {
                    VStack(spacing: 7) {
                        ForEach(workspace.remoteWindows) { window in
                            HStack(spacing: 7) {
                                Image(systemName: window.isMinimized ? "rectangle.dashed" : "macwindow")
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(window.title.isEmpty ? window.applicationName : window.title)
                                        .font(.system(size: 8.5, weight: .semibold))
                                        .lineLimit(1)
                                    Text(window.applicationName)
                                        .font(.system(size: 7))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    workspace.controlRemoteWindow(window, action: window.isMinimized ? .restore : .focus)
                                } label: { Image(systemName: "arrow.up.forward.app") }
                                Button {
                                    workspace.controlRemoteWindow(window, action: window.isMinimized ? .restore : .minimize)
                                } label: { Image(systemName: window.isMinimized ? "plus.rectangle" : "minus.rectangle") }
                                Button(role: .destructive) {
                                    workspace.controlRemoteWindow(window, action: .close)
                                } label: { Image(systemName: "xmark") }
                            }
                            .font(.system(size: 8, weight: .semibold))
                            .buttonStyle(.plain)
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
    }

    private func controlsPanel(size: CGSize) -> some View {
        spatialOverlay(size: size, title: "Spatial Display", icon: "slider.horizontal.3") {
            VStack(spacing: 7) {
                controlSlider("Distance", value: $scene.panelScale, range: 0.58...1.08)
                controlSlider("Eye spacing", value: $scene.eyeSeparation, range: 0...18)
                controlSlider("Comfort", value: $scene.vignetteStrength, range: 0...0.72)
                controlSlider("Lens warp", value: $scene.lensCorrectionStrength, range: 0...0.34)
                controlSlider("Dwell time", value: $scene.dwellDuration, range: 0.65...2.2)

                HStack {
                    Toggle("Gaze dwell", isOn: $scene.dwellEnabled)
                        .font(.system(size: 8, weight: .medium))
                    Toggle("Lens correction", isOn: $scene.lensCorrectionEnabled)
                        .font(.system(size: 8, weight: .medium))
                    Spacer()
                    ForEach(SpatialEnvironment.allCases) { environment in
                        Button(environment.title) { scene.environment = environment }
                            .font(.system(size: 7, weight: .semibold))
                            .buttonStyle(.bordered)
                            .tint(scene.environment == environment ? .cyan : .white.opacity(0.3))
                    }
                }

                HStack(spacing: 7) {
                    Button { scene.panelYaw -= 0.08 } label: { Image(systemName: "arrow.left") }
                    Button { scene.panelPitch += 0.06 } label: { Image(systemName: "arrow.up") }
                    Button("Reset") { scene.resetPanel() }
                    Button { scene.panelPitch -= 0.06 } label: { Image(systemName: "arrow.down") }
                    Button { scene.panelYaw += 0.08 } label: { Image(systemName: "arrow.right") }
                }
                .font(.system(size: 8, weight: .semibold))
                .buttonStyle(.bordered)
            }
        }
    }

    private func controlSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 7.5, weight: .medium))
                .frame(width: 48, alignment: .leading)
            Slider(value: value, in: range)
                .tint(.white)
        }
    }

    private func spatialOverlay<Content: View>(
        size: CGSize,
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 8) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.system(size: 9, weight: .bold))
                Spacer()
                Button { scene.dismissOverlays() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
            }
            Divider().opacity(0.35)
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(.white)
        .padding(11)
        .frame(width: size.width * 0.78, height: size.height * 0.58)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.25), lineWidth: 0.7))
        .shadow(color: .black.opacity(0.4), radius: 22, y: 12)
        .offset(projectedOffset(yaw: overlayAnchorYaw, pitch: overlayAnchorPitch, size: size))
    }

    private var activeWindowTitle: String {
        workspace.remoteWindows.first(where: { !$0.isMinimized })?.title ?? "MACLand Desktop"
    }

    private var remoteAspectRatio: Double {
        let size = workspace.mediaState.displaySize
        guard size.width > 0, size.height > 0 else { return 9.0 / 16.0 }
        return Double(size.width / size.height)
    }

    private func appTint(_ identifier: String) -> Color {
        let colors: [Color] = [.blue, .purple, .pink, .orange, .teal, .indigo]
        return colors[abs(identifier.hashValue) % colors.count]
    }

    private func presentOverlay(_ overlay: SpatialOverlay) {
        overlayAnchorYaw = pose.yaw
        overlayAnchorPitch = pose.pitch
        switch overlay {
        case .launcher: scene.showLauncher()
        case .windows: scene.showWindows()
        case .controls: scene.showControls()
        }
    }

    private func projectedOffset(yaw: Double, pitch: Double, size: CGSize) -> CGSize {
        CGSize(
            width: CGFloat(yaw - pose.yaw) * size.width * 0.92,
            height: -CGFloat(pitch - pose.pitch) * size.height * 0.9
        )
    }

    private func updateDwell(size: CGSize) {
        let target = gazeTarget(size: size)
        guard scene.dwellEnabled,
              Date() >= dwellCooldownUntil,
              target != nil else {
            dwellProgress = 0
            previousYaw = pose.yaw
            previousPitch = pose.pitch
            previousGazeTarget = nil
            return
        }

        let movement = hypot(pose.yaw - previousYaw, pose.pitch - previousPitch)
        previousYaw = pose.yaw
        previousPitch = pose.pitch
        if movement < 0.0038, target == previousGazeTarget {
            dwellProgress += 0.05 / max(scene.dwellDuration, 0.2)
        } else {
            dwellProgress = 0
            previousGazeTarget = target
        }

        if dwellProgress >= 1 {
            performGazeAction(size: size)
            dwellProgress = 0
            dwellCooldownUntil = Date().addingTimeInterval(0.8)
        }
    }

    private var gazePoint: InputPoint? {
        let x = 0.5 + (pose.yaw - scene.panelYaw) * 0.9 / max(scene.panelScale, 0.2)
        let y = 0.5 - (pose.pitch - scene.panelPitch) * 0.9 / max(scene.panelScale, 0.2)
        guard (0...1).contains(x), (0...1).contains(y) else { return nil }
        return InputPoint(
            x: x * Double(workspace.mediaState.displaySize.width),
            y: y * Double(workspace.mediaState.displaySize.height)
        )
    }

    private func performGazeAction(size: CGSize) {
        guard let target = gazeTarget(size: size) else { return }
        HeadsetDeviceSession.selectionFeedback()
        switch target {
        case .desktop:
            guard let point = gazePoint else { return }
            workspace.click(at: point)
        case let .dock(index):
            switch index {
            case 0: presentOverlay(.launcher)
            case 1:
                workspace.refreshRemoteWindows()
                presentOverlay(.windows)
            case 2:
                pose.recenter()
                scene.resetPanel()
            case 3: presentOverlay(.controls)
            default:
                pose.stop()
                onExit()
            }
        case let .application(bundleIdentifier):
            guard let app = workspace.applications.first(where: { $0.bundleIdentifier == bundleIdentifier }) else { return }
            workspace.launchApplication(app)
            scene.dismissOverlays()
        case let .window(id, action):
            guard let window = workspace.remoteWindows.first(where: { $0.id == id }) else { return }
            workspace.controlRemoteWindow(window, action: action)
            if action == .focus || action == .restore { scene.dismissOverlays() }
        case .closeOverlay:
            scene.dismissOverlays()
        case .toggleDwell:
            scene.dwellEnabled.toggle()
        case .toggleLens:
            scene.lensCorrectionEnabled.toggle()
        case let .environment(environment):
            scene.environment = environment
        case .resetDisplay:
            scene.resetPanel()
        }
    }

    private func gazeTarget(size: CGSize) -> SpatialGazeTarget? {
        if scene.isLauncherPresented || scene.isWindowSwitcherPresented || scene.isControlCenterPresented {
            return overlayGazeTarget(size: size)
        }

        let dockOffset = projectedOffset(yaw: scene.panelYaw, pitch: scene.panelPitch - 0.35, size: size)
        let dockWidth = min(size.width * 0.62, 215)
        let localX = -dockOffset.width
        let localY = -dockOffset.height
        if abs(localY) < 22, abs(localX) < dockWidth / 2 {
            let index = min(4, max(0, Int((localX + dockWidth / 2) / (dockWidth / 5))))
            return .dock(index)
        }

        return gazePoint == nil ? nil : .desktop
    }

    private func overlayGazeTarget(size: CGSize) -> SpatialGazeTarget? {
        let overlayWidth = size.width * 0.78
        let overlayHeight = size.height * 0.58
        let offset = projectedOffset(yaw: overlayAnchorYaw, pitch: overlayAnchorPitch, size: size)
        let x = -offset.width / overlayWidth + 0.5
        let y = -offset.height / overlayHeight + 0.5
        guard (0...1).contains(x), (0...1).contains(y) else { return nil }
        if x > 0.82, y < 0.2 { return .closeOverlay }

        if scene.isLauncherPresented {
            guard y > 0.2 else { return nil }
            let column = min(2, max(0, Int(x * 3)))
            let row = max(0, Int((y - 0.2) / 0.24))
            let index = row * 3 + column
            guard workspace.applications.indices.contains(index) else { return nil }
            return .application(workspace.applications[index].bundleIdentifier)
        }

        if scene.isWindowSwitcherPresented {
            guard y > 0.2 else { return nil }
            let row = max(0, Int((y - 0.2) / 0.155))
            guard workspace.remoteWindows.indices.contains(row) else { return nil }
            let window = workspace.remoteWindows[row]
            if x > 0.86 { return .window(window.id, .close) }
            if x > 0.7 { return .window(window.id, window.isMinimized ? .restore : .minimize) }
            return .window(window.id, window.isMinimized ? .restore : .focus)
        }

        guard scene.isControlCenterPresented else { return nil }
        if y > 0.50, y < 0.69 {
            if x < 0.32 { return .toggleDwell }
            if x < 0.62 { return .toggleLens }
            let environmentIndex = min(2, max(0, Int((x - 0.62) / 0.127)))
            return .environment(SpatialEnvironment.allCases[environmentIndex])
        }
        if y > 0.72, x > 0.33, x < 0.67 { return .resetDisplay }
        return nil
    }
}

private enum SpatialOverlay {
    case launcher
    case windows
    case controls
}

private enum SpatialGazeTarget: Equatable {
    case desktop
    case dock(Int)
    case application(String)
    case window(String, WindowCommandAction)
    case closeOverlay
    case toggleDwell
    case toggleLens
    case environment(SpatialEnvironment)
    case resetDisplay

    var label: String {
        switch self {
        case .desktop: "Select"
        case let .dock(index): ["Apps", "Windows", "Center", "Display", "Exit"][min(max(index, 0), 4)]
        case .application: "Open"
        case let .window(_, action): action.rawValue.capitalized
        case .closeOverlay: "Close"
        case .toggleDwell: "Gaze dwell"
        case .toggleLens: "Lens correction"
        case let .environment(environment): environment.title
        case .resetDisplay: "Reset display"
        }
    }
}

private struct CardboardLensCorrection: ViewModifier {
    let enabled: Bool
    let strength: Double
    let chromaticCorrection: Double
    let size: CGSize

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(iOS)
        if enabled {
            content.layerEffect(
                ShaderLibrary.maclandCardboardLens(
                    .float2(Float(size.width), Float(size.height)),
                    .float(Float(strength)),
                    .float(Float(chromaticCorrection))
                ),
                maxSampleOffset: CGSize(width: 36, height: 36)
            )
        } else {
            content
        }
        #else
        content
        #endif
    }
}

@MainActor
private enum HeadsetDeviceSession {
    static func begin() {
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = true
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape)) { _ in }
        }
        #endif
    }

    static func end() {
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = false
        #endif
    }

    static func selectionFeedback() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}

private struct SpatialEnvironmentView: View {
    let environment: SpatialEnvironment
    let headYaw: Double

    var body: some View {
        ZStack {
            LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
            RadialGradient(
                colors: [glow.opacity(0.42), .clear],
                center: UnitPoint(x: CGFloat(0.5 - headYaw * 0.08), y: 0.46),
                startRadius: 4,
                endRadius: 170
            )
            Ellipse()
                .fill(.white.opacity(0.07))
                .frame(width: 320, height: 44)
                .blur(radius: 16)
                .offset(y: 115)
        }
        .ignoresSafeArea()
    }

    private var colors: [Color] {
        switch environment {
        case .dusk: [Color(red: 0.08, green: 0.06, blue: 0.17), Color(red: 0.22, green: 0.12, blue: 0.22), .black]
        case .midnight: [Color(red: 0.01, green: 0.025, blue: 0.07), Color(red: 0.015, green: 0.08, blue: 0.13), .black]
        case .horizon: [Color(red: 0.09, green: 0.16, blue: 0.22), Color(red: 0.34, green: 0.25, blue: 0.22), Color(red: 0.02, green: 0.03, blue: 0.04)]
        }
    }

    private var glow: Color {
        switch environment {
        case .dusk: .purple
        case .midnight: .cyan
        case .horizon: .orange
        }
    }
}

@MainActor
private final class SpatialHeadPoseTracker: ObservableObject {
    @Published private(set) var yaw = 0.0
    @Published private(set) var pitch = 0.0

    #if os(iOS)
    private let motion = CMMotionManager()
    #endif
    private var referenceYaw: Double?
    private var referencePitch: Double?

    func start() {
        #if os(iOS)
        guard motion.isDeviceMotionAvailable else { return }
        referenceYaw = nil
        referencePitch = nil
        motion.deviceMotionUpdateInterval = 1.0 / 90
        motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] sample, _ in
            guard let sample else { return }
            let sampleYaw = sample.attitude.yaw
            let samplePitch = sample.attitude.pitch
            Task { @MainActor [weak self] in
                guard let self else { return }
                if referenceYaw == nil {
                    referenceYaw = sampleYaw
                    referencePitch = samplePitch
                }
                yaw = atan2(sin(sampleYaw - (referenceYaw ?? 0)), cos(sampleYaw - (referenceYaw ?? 0)))
                pitch = samplePitch - (referencePitch ?? 0)
            }
        }
        #endif
    }

    func recenter() {
        #if os(iOS)
        referenceYaw = motion.deviceMotion?.attitude.yaw
        referencePitch = motion.deviceMotion?.attitude.pitch
        #endif
        yaw = 0
        pitch = 0
    }

    func stop() {
        #if os(iOS)
        motion.stopDeviceMotionUpdates()
        #endif
    }
}
