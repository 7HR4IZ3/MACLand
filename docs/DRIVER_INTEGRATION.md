# Third-party display-driver integration

MACLand has two provider paths behind the same typed boundary:

- an experimental VoidDisplay-compatible private `CGVirtualDisplay` bridge, selected for current development;
- a BetterDisplay adapter using its documented notification interface, retained as a future supported-driver option.

The VoidDisplay path is intentionally temporary. It does not pass the supported
public-API gate and must not be treated as production-safe.

## Required driver contract

A candidate driver is acceptable only if it can provide all of these capabilities through documented app, command-line, IPC, or SDK interfaces:

1. Start or enable one dedicated virtual display.
2. Request or select portrait and landscape pixel modes.
3. Report a stable display identity and current mode.
4. Stop or disable the display cleanly.
5. Report driver health and user-approval failures.
6. Work on the supported Apple Silicon/macOS deployment range.
7. Permit a separately signed MACLand host to discover and capture the resulting display.

If a candidate only creates a display through a manual UI and offers no supported automation path, it can be used as a temporary developer prerequisite but does not satisfy the product integration gate.

## Adapter boundary

The host exposes a typed ThirdPartyDisplayDriverAdapter boundary. A vendor
adapter must return the newly created display ID from createDisplay, accept
the requested mode, and implement clean teardown. The default adapter is
intentionally unconfigured and always reports that vendor integration is
required; this prevents a false-positive “ready” state.

The adapter is the only place that should call a vendor SDK, documented IPC
endpoint, private runtime bridge, or documented helper process. The rest of
MACLand interacts through the typed adapter and public display APIs.

## MACLand responsibilities

The host will use public macOS APIs to:

- enumerate active displays;
- identify the driver-provided display after the provider starts it;
- capture that display with ScreenCaptureKit;
- translate phone coordinates into display coordinates;
- inject keyboard and pointer events after Accessibility approval;
- report provider, permission, display, and capture failures to the phone.

The provider must not be treated as ready merely because another external display is connected. MACLand must match the configured provider identity and verify the requested mode before starting a session.

The current host treats unowned external displays as diagnostic candidates
only. A display becomes ready only after the configured adapter returns its
display ID and the public display inventory confirms that the returned ID is
active and non-built-in.

## Current state

The current default is `VoidDisplayDriverAdapter`. It uses a small Objective-C
bridge adapted from VoidDisplay's open-source private-runtime implementation,
creates one named phone-shaped display, retains the runtime display object, and
destroys it through the same boundary. The target Mac has not yet completed a
runtime capture/input smoke test. A direct smoke test has already verified that
the display is recognized by macOS at 1080x1920, the primary display remains
active, and teardown returns the active-display list to its original state.

The BetterDisplay path remains implemented in `BetterDisplayDriverAdapter`, but
the target Mac does not currently have BetterDisplay installed. The target Mac
also has no active non-built-in display before the VoidDisplay path creates one.

BetterDisplay's integration documentation:
https://github.com/waydabber/BetterDisplay/wiki/Integration-features,-CLI

The adapter still requires target-Mac verification for the exact response
payload returned by the installed release, portrait/landscape mode behavior,
and any Pro-license requirement for virtual screens.
