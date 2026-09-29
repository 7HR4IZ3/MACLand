#if os(iOS) && !SWIFT_PACKAGE
import SwiftUI

struct SpatialWorkspaceView: View {
    @ObservedObject var workspace: WorkspaceState
    @StateObject private var session: SpatialSession
    @Environment(\.scenePhase) private var phase
    @State private var entered = false
    @State private var hasProfile = false
    @State private var orientation: UIInterfaceOrientation = .unknown
    private let poll = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    init(workspace: WorkspaceState) {
        self.workspace = workspace
        _session = StateObject(wrappedValue: SpatialSession(workspace: workspace))
    }
    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            let calibratedOrientation = !hasProfile || orientation == .landscapeLeft
            ZStack {
                Color(red: 0.025, green: 0.035, blue: 0.065).ignoresSafeArea()
                if entered && landscape && calibratedOrientation && phase == .active {
                    SpatialMetalView(session: session)
                        .ignoresSafeArea()
                        .onAppear { session.start() }
                        .onDisappear { session.stop() }
                    VStack {
                        HStack {
                            Button { leave() } label: { Image(systemName: "xmark.circle.fill").font(.title2) }
                                .accessibilityLabel("Exit spatial workspace")
                            Spacer()
                        }
                        Spacer()
                    }.padding().tint(.white.opacity(0.6))
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            Image(systemName: "vision.pro").font(.system(size: 38))
                            Text("A space for your Mac").font(.title2.weight(.semibold))
                            Text("Look to aim. Hold to select.").foregroundStyle(.secondary)
                            Text("Face forward, enter, then look below your workspace for Apps and Enable input.")
                                .multilineTextAlignment(.center).frame(maxWidth: 450)
                            HStack {
                                Text("Dwell")
                                Slider(value: $session.dwellDuration, in: 0.6...2, step: 0.1).frame(width: 140)
                                Text("\(session.dwellDuration, specifier: "%.1f") s").monospacedDigit()
                            }
                            if session.optics.available {
                                Button(hasProfile ? "Change viewer profile" : "Scan viewer QR code") { session.optics.scan() }
                                Text(hasProfile ? "Viewer profile saved" : "Scan your Cardboard viewer to calibrate its lenses.")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text("Stereo preview · Cardboard SDK is not included in this build")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                            Button(hasProfile ? "Enter workspace" : "Enter uncalibrated preview") {
                                session.exitRequested = false; entered = true
                            }.buttonStyle(.borderedProminent).disabled(!landscape || !calibratedOrientation || !session.motionAvailable)
                            if !landscape { Text("Rotate your iPhone to landscape").font(.caption) }
                            if landscape && !calibratedOrientation { Text("Rotate to the opposite landscape orientation for this viewer.").font(.caption) }
                            if !session.motionAvailable { Text("Motion sensors are unavailable.").font(.caption) }
                            if let error = session.error { Text(error).font(.caption).foregroundStyle(.orange) }
                            Button("Back to desktop") { session.stop(); workspace.isSpatialPresented = false }
                        }.frame(maxWidth: .infinity).padding(24)
                    }
                }
            }
            .onChange(of: landscape) { _, _ in leave() }
        }
        .preferredColorScheme(.dark)
        .persistentSystemOverlays(.hidden)
        .onReceive(poll) { _ in
            if !entered { hasProfile = session.optics.hasProfile }
            orientation = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.interfaceOrientation ?? .unknown
        }
        .onChange(of: phase) { _, value in if value != .active { leave() } }
        .onChange(of: session.exitRequested) { _, value in if value { leave() } }
        .onDisappear { session.stop() }
    }
    private func leave() { entered = false; session.stop() }
}
#endif
