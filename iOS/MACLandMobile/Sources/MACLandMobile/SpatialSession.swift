#if os(iOS) && !SWIFT_PACKAGE
import SwiftUI
import CoreMotion
import simd

@MainActor
final class SpatialSession: ObservableObject {
    @Published private(set) var status = "Input paused"
    @Published private(set) var error: String?
    @Published var exitRequested = false
    @Published var dwellDuration = 1.2
    let optics = MACLandCardboard()
    let workspace: WorkspaceState
    private let motion = CMMotionManager()
    private var reference: simd_quatf?
    private var lastOrientation: UIInterfaceOrientation?
    private var dwell = SpatialDwell()
    private var lastPointerTime = 0.0
    private var wasUsable = false
    private var motionIsFresh = false
    private var mode = 0 // click, right-click, double-click
    private var appPage = 0
    private var launcher = false
    private var blockedControl: String?
    private(set) var armed = false
    private(set) var head = matrix_identity_float4x4
    private(set) var reticle = SIMD3<Float>(0, 0, -2.2)
    private(set) var activeID: String?
    private(set) var surfaces: [SpatialSurface] = []
    var progress: Float { Float(dwell.progress) }
    var motionAvailable: Bool { motion.isDeviceMotionAvailable }
    private var savedIdleTimer = false
    private var running = false
    private var scale: Float {
        get { let value = UserDefaults.standard.float(forKey: "spatial.windowScale"); return value == 0 ? 1 : min(1.35, max(0.75, value)) }
        set { UserDefaults.standard.set(newValue, forKey: "spatial.windowScale") }
    }

    init(workspace: WorkspaceState) { self.workspace = workspace; rebuild() }

    func reportRenderError(_ message: String) { error = message; pause() }

    func start() {
        guard !running else { return }
        running = true
        savedIdleTimer = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        motion.deviceMotionUpdateInterval = 1.0 / 90
        motion.startDeviceMotionUpdates(using: .xArbitraryZVertical)
        recenter(); pause()
        try? workspace.controlClient.requestApplications()
    }
    func stop() {
        pause(); motion.stopDeviceMotionUpdates()
        if running { UIApplication.shared.isIdleTimerDisabled = savedIdleTimer }
        running = false; reference = nil; motionIsFresh = false
    }
    func pause() { armed = false; dwell.reset(); activeID = nil; status = "Input paused"; rebuild() }
    func recenter() { reference = nil; dwell.reset(); head = matrix_identity_float4x4 }

    /// Called from the display loop, not from the stream callback.
    func update(time: Double, orientation: UIInterfaceOrientation, videoFresh: Bool) {
        if lastOrientation != orientation { recenter(); pause(); lastOrientation = orientation }
        motionIsFresh = false
        if let sample = motion.deviceMotion, time - sample.timestamp < 0.25 {
            motionIsFresh = true
            let q = sample.attitude.quaternion
            let current = simd_quatf(ix: Float(q.x), iy: Float(q.y), iz: Float(q.z), r: Float(q.w))
            if reference == nil { reference = current }
            if let reference {
                let basis = simd_quatf(angle: orientation == .landscapeRight ? -.pi/2 : .pi/2,
                                      axis: SIMD3<Float>(0, 0, 1))
                head = simd_float4x4(basis.inverse * (reference.inverse * current) * basis)
            }
        }
        let usable = workspace.connectionState.isConnected && workspace.mediaState.connectionState == .connected && videoFresh && motionIsFresh
        if !usable && wasUsable { pause() }
        wasUsable = usable
        if !motionIsFresh { dwell.reset(); activeID = nil; return }
        rebuild()
        let direction = -SIMD3<Float>(head.columns.2.x, head.columns.2.y, head.columns.2.z)
        let hit = SpatialGeometry.hit(direction: direction, surfaces: surfaces)
        reticle = hit?.point ?? direction * 2.2
        activeID = hit?.id
        if hit?.id != blockedControl { blockedControl = nil }
        guard let hit else { dwell.reset(); return }
        if hit.id == blockedControl { dwell.reset(); return }
        if hit.id == "display" && (!armed || !usable) { dwell.reset(); return }
        let stablePoint = hit.id == "display" ? SIMD2<Float>(hit.point.x, hit.point.y) : .zero
        let activated = dwell.update(target: hit.id, point: stablePoint, time: time, duration: dwellDuration)
        if hit.id == "display" {
            guard time - lastPointerTime >= 1.0 / 30 || activated else { return }
            lastPointerTime = time
            sendPointer(hit: hit, click: activated)
        } else if activated {
            blockedControl = hit.id
            activate(hit.id, usable: usable)
        }
    }

    private func rebuild() {
        let aspect = Float(workspace.mediaState.displaySize.width / max(1, workspace.mediaState.displaySize.height))
        let height = min(1.45, 2.4 / max(0.1, aspect)) * scale
        surfaces = []
        if !launcher {
            surfaces.append(SpatialSurface(id: "display", center: SIMD3(0, 0.15, -2.2),
                size: SIMD2(height * aspect, height), title: workspace.mediaState.connectionState.label,
                symbol: "display", isDisplay: true))
        } else {
            let apps = workspace.controlClient.applications
            let start = min(appPage * 6, max(0, apps.count - 1))
            for (index, app) in apps.dropFirst(start).prefix(6).enumerated() {
                surfaces.append(SpatialSurface(id: "app:" + app.bundleIdentifier,
                    center: SIMD3(Float(index % 3 - 1) * 0.68, 0.52 - Float(index / 3) * 0.48, -2.2),
                    size: SIMD2(0.62, 0.40), title: app.name, symbol: app.isRunning ? "app.fill" : "app"))
            }
            if apps.isEmpty {
                surfaces.append(SpatialSurface(id: "refresh", center: SIMD3(0, 0.2, -2.2),
                    size: SIMD2(1.5,0.5), title: "Refresh Mac apps", symbol: "arrow.clockwise"))
            }
        }
        let buttons: [(String,String,String)] = [
            ("apps", launcher ? "Desktop" : "Apps", launcher ? "display" : "square.grid.2x2"),
            ("arm", armed ? "Pause" : "Enable input", armed ? "pause.fill" : "cursorarrow"),
            ("mode", ["Click", "Right click", "Double click"][mode], "cursorarrow.click"),
            ("recenter", "Recenter", "scope"),
            ("exit", "Exit", "xmark")
        ]
        for (i, item) in buttons.enumerated() {
            surfaces.append(SpatialSurface(id: item.0, center: SIMD3(Float(i - 2)*0.45, -1.04, -2.2),
                                          size: SIMD2(0.41,0.27), title: item.1, symbol: item.2))
        }
        let secondary: [(String,String,String)] = launcher
            ? [("previous", "Previous", "chevron.left"), ("refresh", "Refresh", "arrow.clockwise"), ("next", "Next", "chevron.right")]
            : [("pageup", "Page up", "arrow.up"), ("size", "Window size", "arrow.up.left.and.arrow.down.right"), ("pagedown", "Page down", "arrow.down")]
        for (i, item) in secondary.enumerated() {
            surfaces.append(SpatialSurface(id: item.0, center: SIMD3(Float(i-1)*0.55, -1.42, -2.2),
                                          size: SIMD2(0.5,0.25), title: item.1, symbol: item.2))
        }
    }

    private func activate(_ id: String, usable: Bool) {
        do {
            switch id {
            case "arm":
                if armed { pause() }
                else if usable { armed = true; status = "Gaze input active" }
                else { status = "Wait for a live Mac stream" }
            case "apps": launcher.toggle(); armed = false; appPage = 0; try workspace.controlClient.requestApplications()
            case "mode": mode = (mode + 1) % 3
            case "recenter": recenter(); pause()
            case "exit": stop(); exitRequested = true
            case "size": scale = scale < 1 ? 1 : scale < 1.3 ? 1.35 : 0.75
            case "previous": appPage = max(0, appPage - 1)
            case "next": appPage = min(max(0, (workspace.controlClient.applications.count - 1) / 6), appPage + 1)
            case "refresh": try workspace.controlClient.requestApplications()
            case "pageup", "pagedown":
                guard armed && usable else { return }
                let timestamp = UInt64(Date().timeIntervalSince1970 * 1000)
                let key: UInt16 = id == "pageup" ? 116 : 121
                try workspace.controlClient.sendInput(events: [
                    InputEvent(kind: .key, timestamp: timestamp, pressed: true, keyCode: key),
                    InputEvent(kind: .key, timestamp: timestamp, pressed: false, keyCode: key)])
            default:
                if id.hasPrefix("app:"), workspace.connectionState.isConnected {
                    try workspace.controlClient.launchApplication(bundleIdentifier: String(id.dropFirst(4)))
                    launcher = false; armed = false; status = "Input paused"
                }
            }
            error = nil; rebuild()
            // Keep the dwell latch until the user leaves this control.
        } catch { self.error = error.localizedDescription; pause() }
    }

    private func sendPointer(hit: SpatialHit, click: Bool) {
        let display = workspace.mediaState.displaySize
        let location = InputPoint(x: Double(hit.uv.x) * max(0, display.width - 1),
                                  y: Double(hit.uv.y) * max(0, display.height - 1))
        let timestamp = UInt64(Date().timeIntervalSince1970 * 1000)
        var events = [InputEvent(kind: .pointerMove, timestamp: timestamp, location: location)]
        if click {
            let button: MouseButton = mode == 1 ? .right : .left
            for count in 1...(mode == 2 ? 2 : 1) {
                events.append(InputEvent(kind: .pointerButton, timestamp: timestamp, location: location,
                                         button: button, pressed: true, clickCount: count))
                events.append(InputEvent(kind: .pointerButton, timestamp: timestamp, location: location,
                                         button: button, pressed: false, clickCount: count))
            }
        }
        do { try workspace.controlClient.sendInput(events: events) }
        catch { self.error = error.localizedDescription; pause() }
    }
}
#endif
