import Foundation
import SwiftUI

#if canImport(WebRTC) && !SWIFT_PACKAGE
@preconcurrency import WebRTC
public typealias NativeRemoteVideoTrack = RTCVideoTrack
#else
public typealias NativeRemoteVideoTrack = Any
#endif

public enum RemoteMediaConnectionState: String, CaseIterable, Sendable {
    case idle
    case negotiating
    case connected
    case reconnecting
    case failed

    public var label: String {
        switch self {
        case .idle: "Media idle"
        case .negotiating: "Negotiating media"
        case .connected: "Media connected"
        case .reconnecting: "Reconnecting media"
        case .failed: "Media unavailable"
        }
    }
}

@MainActor
public final class RemoteMediaState: ObservableObject {
    @Published public private(set) var connectionState: RemoteMediaConnectionState = .idle
    @Published public private(set) var failureMessage: String?
    @Published public private(set) var displaySize = CGSize(width: 1080, height: 1920)
    public let webRTCClient: NativeWebRTCClient

    public init(webRTCClient: NativeWebRTCClient = NativeWebRTCClient()) {
        self.webRTCClient = webRTCClient
    }

    public func beginNegotiation() {
        failureMessage = nil
        connectionState = .negotiating
    }

    public func markConnected() {
        failureMessage = nil
        connectionState = .connected
    }

    public func markReconnecting() {
        connectionState = .reconnecting
    }

    public func markFailed(_ message: String) {
        failureMessage = message
        connectionState = .failed
    }

    public func reset() {
        failureMessage = nil
        connectionState = .idle
    }

    public func updateDisplaySize(width: Int, height: Int) {
        guard width > 0, height > 0 else { return }
        displaySize = CGSize(width: width, height: height)
    }
}

#if canImport(UIKit) && canImport(WebRTC)
import AVFoundation
import UIKit

@MainActor
public final class NativeWebRTCAudioOutput {
    public init() {}

    public func activate() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
        try audioSession.setActive(true)
    }

    public func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}

public struct NativeWebRTCVideoSurface: UIViewRepresentable {
    public let videoTrack: NativeRemoteVideoTrack?

    public init(videoTrack: NativeRemoteVideoTrack? = nil) {
        self.videoTrack = videoTrack
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView(frame: .zero)
        view.videoContentMode = .scaleAspectFit
        context.coordinator.attach(videoTrack, to: view)
        return view
    }

    public func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {
        context.coordinator.attach(videoTrack, to: uiView)
    }

    public static func dismantleUIView(_ uiView: RTCMTLVideoView, coordinator: Coordinator) {
        coordinator.detach(from: uiView)
    }

    @MainActor
    public final class Coordinator {
        private weak var attachedTrack: RTCVideoTrack?
        private weak var attachedRenderer: RTCMTLVideoView?

        fileprivate func attach(_ track: RTCVideoTrack?, to renderer: RTCMTLVideoView) {
            if attachedTrack !== track || attachedRenderer !== renderer {
                if let attachedTrack, let attachedRenderer {
                    attachedTrack.remove(attachedRenderer)
                }
                if let track {
                    track.add(renderer)
                }
                attachedTrack = track
                attachedRenderer = renderer
            }
        }

        fileprivate func detach(from renderer: RTCMTLVideoView) {
            attachedTrack?.remove(renderer)
            attachedTrack = nil
            attachedRenderer = nil
        }
    }
}
#else
@MainActor
public final class NativeWebRTCAudioOutput {
    public init() {}
    public func activate() throws {}
    public func deactivate() {}
}

public struct NativeWebRTCVideoSurface: View {
    public init(videoTrack: NativeRemoteVideoTrack? = nil) {
        _ = videoTrack
    }

    public var body: some View {
        Color.black
            .overlay {
                Text("Native WebRTC video is available on iOS")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
    }
}
#endif
