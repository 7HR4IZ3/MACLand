# MACLand

MACLand is evolving into an iPhone spatial desktop powered by a Mac, with head-directed gaze controls for a Cardboard-style viewer. The Mac runs applications; the iPhone renders the workspace locally.

See [the spatial redesign](docs/SPATIAL_WORKSPACE.md) for the architecture, interaction model, implementation stages and device acceptance checks. The headset icon in a remote session opens a Metal spatial workspace with head tracking, gaze dwell controls and a Mac app launcher. Run `bash scripts/setup-cardboard.sh` on your Mac to build the pinned Cardboard SDK and enable viewer QR calibration and lens distortion. Builds without the SDK remain explicitly uncalibrated stereo previews.

## Current status

The project now contains:

- a native SwiftUI iOS shell with launcher, dock, task switching, settings, pairing state, and coordinate mapping;
- a native menu-bar macOS host with application discovery, permission onboarding, LAN Bonjour advertisement, typed protocol routing, and Accessibility input primitives;
- a persistent dark menu-bar utility panel with section navigation for displays, media, apps, controls, and settings;
- a shared versioned JSON control protocol with request IDs, sequence numbers, capability negotiation, permission state, app commands, display commands, clipboard, media negotiation, and structured errors;
- reproducible SwiftPM and Xcode build/test targets.

The supported public virtual-display gate is still blocked: the installed macOS SDK exposes no supported public host-side virtual-display API. For the current experiment, the host uses a narrowly isolated VoidDisplay-compatible private `CGVirtualDisplay` bridge, selected explicitly as a temporary development path. It is not a production or App Store-safe implementation. See [docs/FEASIBILITY.md](docs/FEASIBILITY.md).

The current integration is buildable but not yet device-validated end-to-end. The host now has the TLS WebSocket listener, pairing-code approval, typed command routing, ScreenCaptureKit display capture, and native WebRTC M150 sender. The iOS client has Bonjour discovery, pinned WSS trust evaluation, signaling, reconnect handling, native WebRTC surface plumbing, dynamic display geometry, and pointer/app command routes.

The host TLS listener intentionally fails closed until a certificate and private-key identity is installed in the login keychain under `com.thraize.macland.host.tls`. Pairing approval is currently an in-memory development control, and the host menu copies pairing JSON for paste into the iOS Settings screen; a QR scanner and persistent device revocation UI are still pending. System audio capture is exposed by the ScreenCaptureKit layer, but audio track publishing is not yet enabled in the WebRTC sender. Terminal control remains disabled by default.

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
