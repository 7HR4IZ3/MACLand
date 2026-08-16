# VoidDisplay extraction manifest

MACLand uses a reviewed snapshot of the public [7HR4IZ3/VoidDisplay fork](https://github.com/7HR4IZ3/VoidDisplay), derived from upstream [iamsyc/VoidDisplay](https://github.com/iamsyc/VoidDisplay).

Pinned upstream commit:

```text
1169fcd2e51103746976b2b2cd27c112f3e13082
build(webrtc): upgrade WebRTC to M150 and remove local header patch
```

The fork is provenance and review infrastructure. MACLand does not consume the
full VoidDisplay Swift package or its application product.

## Extraction boundary

| Upstream area | MACLand use | Deliberately excluded |
| --- | --- | --- |
| `Sources/CGVirtualDisplayPrivate` | Private display declarations and runtime bridge | VoidDisplay app shell |
| `Sources/VoidDisplayCGVirtualDisplay/Runtime/CGVirtualDisplayRuntimeDriver.swift` | Adapted display creation, settings, identity, and termination behavior | VoidDisplay configuration UI and persistence |
| Selected `Sources/VoidDisplayCapture` concepts | ScreenCaptureKit display video/audio capture | Preview windows and capture UI |
| Selected `Sources/VoidDisplaySharing/Web` concepts | WebRTC publisher, codec negotiation, and signaling model | Browser resources and VoidDisplay LAN server |

Every copied or adapted file must retain an upstream path, pinned commit, and
modification note in its header or in the nearest extraction manifest entry.
Updates are manual: review the upstream diff, update this SHA, rerun the
capture/media tests, and verify the private runtime on the target macOS release.

## MACLand extraction locations

| MACLand path | Role | Provenance |
| --- | --- | --- |
| `MacHost/Sources/MACLandHost/VoidDisplayPrivate/CGVirtualDisplayPrivate.h` | Private display declarations | Adapted from `Sources/CGVirtualDisplayPrivate` |
| `MacHost/Sources/MACLandHost/VoidDisplayPrivate/MACLandVoidDisplayBridge.*` | MACLand-owned lifecycle bridge | Derived from the private runtime path; reduced to create/reconfigure/destroy |
| `MacHost/Sources/MACLandHost/VoidDisplayExtracted/VoidDisplayCapturePermission.swift` | Screen Recording state | Adapted capture permission concept |
| `MacHost/Sources/MACLandHost/VoidDisplayExtracted/VoidDisplayCaptureTypes.swift` | Capture geometry and state | Adapted capture types |
| `MacHost/Sources/MACLandHost/VoidDisplayExtracted/VoidDisplayScreenCaptureSession.swift` | Whole-display video/audio capture | Adapted ScreenCaptureKit path |
| `MacHost/Sources/MACLandHost/VoidDisplayExtracted/VoidDisplayWebRTC.swift` | Native WebRTC sender and codec policy | Adapted sharing/media path |
| `MacHost/Sources/MACLandHost/VoidDisplayExtracted/VoidDisplayMediaCoordinator.swift` | MACLand capture/signaling lifecycle | MACLand-owned integration around the adapted components |

The host's secure WebSocket, pairing, app-control, and iOS SwiftUI shell are
MACLand code and are not copied from VoidDisplay.

## Related dependencies

The initial WebRTC dependency is pinned to `stasel/WebRTC` `150.0.0`, matching
the selected VoidDisplay snapshot. Its license and notices remain separate
third-party material and must be included in any distributable build.
