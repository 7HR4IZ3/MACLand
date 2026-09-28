# MACLand

MACLand is an iPhone spatial desktop shell for controlling a Mac through a dedicated remote display, including a side-by-side headset view for phone VR viewers.

## Current status

The project now contains:

- a native SwiftUI iOS shell with launcher, dock, task switching, settings, pairing state, and coordinate mapping;
- a native menu-bar macOS host with application discovery, permission onboarding, LAN Bonjour advertisement, typed protocol routing, and Accessibility input primitives;
- a persistent dark menu-bar utility panel with section navigation for displays, media, apps, controls, and settings;
- a shared versioned JSON control protocol with request IDs, sequence numbers, capability negotiation, permission state, app commands, display commands, clipboard, media negotiation, and structured errors;
- reproducible SwiftPM and Xcode build/test targets.

The supported public virtual-display gate is still blocked: the installed macOS SDK exposes no supported public host-side virtual-display API. For the current experiment, the host uses a narrowly isolated VoidDisplay-compatible private `CGVirtualDisplay` bridge, selected explicitly as a temporary development path. It is not a production or App Store-safe implementation. See [docs/FEASIBILITY.md](docs/FEASIBILITY.md).

The current integration is not yet device-validated end-to-end. The host has a TLS WebSocket listener, pairing codes that expire after ten minutes, bidirectional ICE signaling, typed command routing, ScreenCaptureKit display capture, Unicode text and click injection, and a native WebRTC M150 sender. The iOS client has Bonjour discovery, pinned WSS trust evaluation, signaling, reconnect handling, a side-by-side viewer with CoreMotion head tracking and gaze selection, a Mac app launcher, a native WebRTC surface, and dynamic display geometry.

Tap **Headset** in the remote session, rotate the phone to landscape, and place it in a compatible phone VR holder. Each eye shows the same Mac video track. Use **Center** to recenter, **Select** or a screen-tapping viewer button to click, **Apps** to open a Mac app, and **Type** to send text. Remove the phone from the holder to use the system keyboard. This is an app-based spatial shell over macOS, not a replacement for iOS or macOS. The display is monoscopic and has no viewer-specific lens distortion calibration or spatial window compositor yet; see [headset limitations](docs/CARDBOARD_SPATIAL_OS.md).

The host TLS listener intentionally fails closed until a certificate and private-key identity is installed in the login keychain under `com.thraize.macland.host.tls`. Pairing approval is currently an in-memory development control; use **New code** after ten minutes, then copy fresh pairing JSON into iOS Settings. A QR scanner and persistent device revocation UI are still pending. System audio capture is exposed by the ScreenCaptureKit layer, but audio track publishing is not yet enabled in the WebRTC sender. Terminal control remains disabled by default.

The selected development path is documented in [docs/DRIVER_INTEGRATION.md](docs/DRIVER_INTEGRATION.md). The default host provider is now the experimental VoidDisplay bridge. The BetterDisplay adapter remains in the codebase as a future supported-driver option. The direct private-display smoke test has verified a macOS-recognized 1080x1920 display, primary-display stability, and teardown; a real Mac-to-iPhone WebRTC, permissions, rotation, reconnect, and input run remains required.

The VoidDisplay extraction provenance and copied-source boundary are recorded in [docs/VOIDDISPLAY_SOURCE_MANIFEST.md](docs/VOIDDISPLAY_SOURCE_MANIFEST.md). MACLand uses its own secure transport and native client; VoidDisplay's browser LAN server is not the product transport.

## Build and test

The checked-in Xcode project can be built directly from Xcode or with `xcodebuild`. From the repository root:

```sh
xcodebuild -project MACLand.xcodeproj -scheme MACLandHost -sdk macosx build CODE_SIGNING_ALLOWED=NO
xcodebuild -project MACLand.xcodeproj -scheme MACLandMobile -sdk iphonesimulator build CODE_SIGNING_ALLOWED=NO
```

SwiftPM tests are available from their package directories:

```sh
(cd Shared/MACLandProtocol && swift test -q)
(cd iOS/MACLandMobile && swift test -q)
bash scripts/check-virtual-display-api.sh
```

The virtual-display check intentionally exits with status `2` until a supported Apple display-extension path is proven.
