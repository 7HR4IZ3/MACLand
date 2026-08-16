import SwiftUI

@MainActor
public struct MACLandDesktopView: View {
    @StateObject private var workspace: WorkspaceState

    public init(workspace: WorkspaceState = WorkspaceState()) {
        _workspace = StateObject(wrappedValue: workspace)
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            MACLandHomeView(workspace: workspace)

            if workspace.isLauncherPresented {
                LauncherOverlay(workspace: workspace)
            }

            if workspace.isTaskSwitcherPresented {
                TaskSwitcherOverlay(workspace: workspace)
            }
        }
        .preferredColorScheme(.dark)
#if os(iOS)
        .fullScreenCover(isPresented: remoteFullscreenBinding) {
            RemoteSessionFullscreenView(workspace: workspace)
        }
#else
        .sheet(isPresented: remoteFullscreenBinding) {
            RemoteSessionFullscreenView(workspace: workspace)
        }
#endif
    }

    private var remoteFullscreenBinding: Binding<Bool> {
        Binding(
            get: { workspace.isRemoteFullscreen },
            set: { workspace.isRemoteFullscreen = $0 }
        )
    }
}
