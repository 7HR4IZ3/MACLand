# MACLand spatial workspace

## Product definition

An iPhone spatial desktop powered by a Mac, viewed through a Cardboard-style
headset. macOS runs applications and owns their state. iOS owns the environment,
head pose, reticle, targeting and compositor. This is an OS-like shell running
inside an iOS app, not a replacement operating system or visionOS port.

Gaze means a ray pointing out from the center of the user's head. No eye tracking,
hand tracking, camera passthrough, room mapping or positional tracking is required.
The experience is seated and orientation-only: turning changes the view; leaning
or walking does not move the viewpoint through the virtual space.

## Repository assessment

- MacHost: menu-bar app, permission onboarding, app catalog and window operations,
  virtual-display adapters, ScreenCaptureKit capture and native WebRTC sender.
- Shared/MACLandProtocol: versioned messages, pairing, display and application
  commands, media signaling and batched pointer/keyboard input.
- iOS/MACLandMobile: SwiftUI desktop, discovery/pairing, pinned TLS WebSocket,
  WebRTC receiver, touch coordinate mapping and remote fullscreen presentation.
- The baseline has one streamed display, not separately textured app windows.
- Private CGVirtualDisplay is isolated but remains a distribution risk. The README
  also identifies manual TLS installation, temporary pairing state, missing audio
  publishing and incomplete end-to-end device validation.

## Experience redesign

Before insertion, the phone presents Mac discovery, pairing, host permission
status, viewer scan and comfort calibration. Once inside, a quiet dark environment
contains a large floating Mac workspace. A curved dock below it provides Home,
Apps, Spaces, Input and Recenter. Glass-like surfaces and restrained highlights
provide a visionOS-inspired hierarchy without reproducing its interaction model.

The initial supported workspace is one Mac desktop surface. Later, independently
captured windows can form a persistent arc around the viewer. App launch must not
pretend to create an independent spatial window until that capture route exists.

Head rotation aims a visible reticle. A progress ring communicates dwell; moving
away cancels selection. After firing, the target must be left before reactivation.
Looking down pauses/resumes input. Browsing or watching video should work while
input is paused. Future explicit modes handle right click, double click, scrolling
and dragging; simply looking at a desktop must not accidentally start a drag.
Text entry should first support a physical keyboard, then a large dwell keyboard.
Nod confirmation is optional future work, with deliberate arming and debounce;
ordinary head movement should never trigger a command.

## Implemented in this branch

The headset icon in a connected remote session opens the spatial setup screen.
The scene is now rendered by one Metal compositor with two eye cameras, a shared
video texture, perspective-correct world surfaces and a depth-correct reticle.
Core Motion supplies relative orientation including roll. The same surface bounds
are used by the GPU and the CPU gaze raycaster. The video mailbox keeps only the
latest decoded frame; the compositor runs independently at a target 60 Hz. Hardware
pixel buffers stay on the GPU conversion path; I420 decoding has an NV12 fallback.

The gaze dock provides the real Mac application catalog (six apps per page),
launching, input enable/pause, click/right-click/double-click modes, recenter, window
size, page-up/page-down and exit. App launching operates on the existing streamed
Mac desktop, not independent captured window streams. The window scale persists.
Dwell duration is configurable. Holding on a control cannot repeatedly activate it.
Remote input requires a decoded frame, connected media and fresh motion. ICE/media
loss pauses input; returning to the session starts paused. Static desktop frames
remain usable while the peer connection is healthy. Backgrounding, rotation and
exit restore the idle timer and release tracking/render resources.

The Mac injector now uses the correct mouse event type for right/middle buttons
and accepts an optional, backward-compatible click count for double clicks.

### Cardboard setup on your Mac

Requirements: Xcode, CocoaPods (`pod`), XcodeGen, Git and Python 3. Run:

```sh
bash scripts/setup-cardboard.sh
./macland.sh "build ios client"
```

The setup script builds Google Cardboard at pinned commit
`5969239e7c87f4cd64c8ec170ce1e7f4eb559e37` and its pinned Protobuf-C++ 3.18.0
dependency for device and simulator. It combines the static libraries into a local
XCFramework, includes SDK resources and licenses, and generates an XcodeGen
overlay. Subsequent `macland.sh` builds preserve this overlay.

In the app, scan the viewer's QR code before entry. The Objective-C++ bridge uses
its saved parameters for per-eye projection matrices, eye transforms and the
SDK's Metal distortion mesh. Calibrated mode uses landscape-left, matching the
Cardboard iOS reference implementation. If the SDK or profile is absent, the app
explicitly offers an uncalibrated stereo preview; it never substitutes guessed
lens coefficients. The preview uses 64 mm eye separation and 60-degree vertical
field of view. Pair with the Mac before entering the spatial view.

### Validation and remaining work

Tests cover ray hits, pixel-coordinate convention, depth ordering, misses,
dwell jitter, cancellation and rearming, plus optional protocol click counts.
The Apple CI workflow builds the preview, host and calibrated app and runs the
protocol and mobile model tests. The editing environment cannot run Xcode; actual
Apple compilation and device/optical checks must be reported separately.

This implementation delivers a spatial shell around one live Mac desktop.
Independent per-app captured streams, drag mode, a gaze keyboard, audio publishing,
persistent host trust management and automated host TLS installation remain
separate work. No claim of visionOS parity or device-validated comfort is made.

## Acceptance checks on Mac + iPhone

- Both landscape orientations: turn left/right/up/down; aim and pointer agree.
- Recenter, yaw wrap and changing orientation produce no jumps or clicks.
- Verify reticle mapping at center and all four edges for portrait/landscape
  remote displays; letterboxes never receive clicks.
- Dwell fires once while stationary; moving away cancels/rearms; look-down pause
  remains available without a live Mac stream.
- Reconnect, interrupted media, lock/unlock, exit and re-entry cannot retain an
  armed click or a pressed mouse button.
- Profile motion-to-photon latency, network latency, frame drops, decoding,
  thermal behavior and battery drain over a 20-minute session on the target phone.
- Complete the viewer-profile distortion step before evaluating headset comfort.

## Primary implementation references

- https://developers.google.com/cardboard/develop/ios/quickstart
- https://developers.google.com/cardboard/reference/c
- https://developer.apple.com/documentation/coremotion/cmmotionmanager
