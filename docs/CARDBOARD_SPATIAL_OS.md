# Cardboard spatial desktop

The product is an iPhone app that presents a Mac-hosted desktop in a phone VR viewer. Mac apps still run on macOS. The iPhone cannot replace iOS as the device operating system or expose arbitrary Mac app windows as native iOS windows.

## Implemented path

1. Pair the iPhone with the macOS host using pinned TLS and the host's time-limited JSON code.
2. The host creates its experimental virtual display, captures its pixels, and streams one WebRTC video track over the LAN.
3. Tap **Headset** in the iPhone session and rotate to landscape. The virtual scene is rendered separately for both eye regions. CoreMotion updates the scene from head rotation; it does not use eye tracking, hand tracking, passthrough, or room position tracking.
4. The reticle stays at the center of view. Rotate your head to point it at the dock, an overlay item, or the Mac display, then press the viewer button or enable dwell selection. This head-gaze interaction opens applications, focuses/minimizes/restores/closes Mac windows, recenters the scene, changes display settings, or clicks the Mac desktop.
5. The final per-eye scene passes through an adjustable Metal lens pre-warp with edge masking and chromatic correction. **Display** exposes lens strength, eye spacing, comfort vignette, and dwell timing. These settings persist on the phone.
6. Tap **Exit VR** to use the flat remote desktop; touch drags move the pointer, and a tap clicks.

## Still required for a comfortable spatial OS

| Area | Current boundary | Next implementation |
| --- | --- | --- |
| Optics | Adjustable GPU lens pre-warp and eye alignment; calibration is manual and both eyes still receive the same camera view | Replace manual coefficients with the Cardboard SDK QR-derived distortion mesh and per-eye projection |
| Spatial windows | The shell can list and control real Mac windows, but video is still one virtual-display surface | Capture each `SCWindow` into its own WebRTC track and compose independently movable panels |
| Tracking | Head rotation from the phone's motion sensors, with manual recenter; the virtual space does not track physical position | Keep rotational tracking responsive and recentering easy |
| Interaction | Head-centered reticle with viewer-button and dwell activation for the dock, launcher, window switcher, display controls, and desktop clicks | Add Bluetooth controller bindings, scroll/drag gestures, and ergonomic in-headset text input |
| Sound | Mac system audio is captured but not published to the WebRTC sender | Publish synchronized audio and confirm iPhone playback |
| Display driver | Experimental private `CGVirtualDisplay` bridge | Replace with an approved external driver or supported Apple API if one becomes available |
| Onboarding | Manual pairing JSON and preinstalled TLS identity | Add an identity setup flow and camera QR scanner |
| Reachability | Local-network ICE candidates only | Add optional STUN/TURN configuration for access outside the LAN |

The new Apple build workflow checks the shared protocol and both app targets on a macOS runner. Physical iPhone plus Mac testing is still needed for orientation, frame latency, permissions, accessibility input, and the exact phone viewer's optics.

The current lens shader is a useful development profile, not a substitute for viewer QR calibration. Different headsets have different screen-to-lens distances, field of view, and distortion coefficients. Start with a low warp value, center the phone precisely, and increase it until straight lines remain stable near the lens edges.
