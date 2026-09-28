# Cardboard spatial desktop

The product is an iPhone app that presents a Mac-hosted desktop in a phone VR viewer. Mac apps still run on macOS. The iPhone cannot replace iOS as the device operating system or expose arbitrary Mac app windows as native iOS windows.

## Implemented path

1. Pair the iPhone with the macOS host using pinned TLS and the host's time-limited JSON code.
2. The host creates its experimental virtual display, captures its pixels, and streams one WebRTC video track over the LAN.
3. Tap **Headset** in the iPhone session and rotate to landscape. The track appears separately in both eye regions; CoreMotion pans the display relative to the center reticle.
4. Tap the display, use the viewer's screen-tapping button, or choose **Select** to send a Mac click at the reticle. **Center** recalibrates the head direction. **Apps** opens the host app catalog and launches or focuses a Mac app. **Type** sends Unicode text from an iPhone keyboard sheet.
5. Tap **Exit VR** to use the flat remote desktop; touch drags move the pointer, and a tap clicks.

## Still required for a comfortable spatial OS

| Area | Current boundary | Next implementation |
| --- | --- | --- |
| Optics | Same flat image in both eyes; no lens distortion, inter-pupillary distance setting, or viewer QR calibration | Integrate Cardboard SDK optical calibration and low-latency stereo distortion compositor |
| Spatial windows | One Mac virtual display, not independently placed application surfaces | Capture/window-track individual Mac windows and compose movable 3D panels |
| Tracking | Gyroscope attitude with manual recenter; no world tracking or positional depth | Add a tracked camera-based mode where device support and permissions allow |
| Interaction | Screen tap/gaze click and iPhone keyboard sheet | Add a configurable viewer-button/controller binding and ergonomic in-headset text input |
| Sound | Mac system audio is captured but not published to the WebRTC sender | Publish synchronized audio and confirm iPhone playback |
| Display driver | Experimental private `CGVirtualDisplay` bridge | Replace with an approved external driver or supported Apple API if one becomes available |
| Onboarding | Manual pairing JSON and preinstalled TLS identity | Add an identity setup flow and camera QR scanner |
| Reachability | Local-network ICE candidates only | Add optional STUN/TURN configuration for access outside the LAN |

The new Apple build workflow checks the shared protocol and both app targets on a macOS runner. Physical iPhone plus Mac testing is still needed for orientation, frame latency, permissions, accessibility input, and the exact phone viewer's optics.
