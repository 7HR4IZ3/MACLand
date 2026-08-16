# MACLand feasibility gate

## Virtual display status

The first implementation gate is a supported virtual display. MACLand must not use private `CGS` or SkyLight symbols as a substitute.

The current development machine is Apple Silicon running macOS 27.0 with Xcode 27. The installed SDK imports CoreGraphics, but its public headers do not declare `CGVirtualDisplay`, `CGVirtualDisplayDescriptor`, or `CGVirtualDisplaySettings`. A direct Swift compiler check also fails to resolve `CGVirtualDisplay`.

Run the reproducible check with:

```sh
bash scripts/check-virtual-display-api.sh
```

The expected current result is exit code `2` with a blocked-gate message. This is an intentional stop condition: the host must not create a fake display through private APIs, hidden windows, or a normal Mission Control Space.

## What remains to be proven

The gate can only move to `passed` after a supported Apple display-extension or system-extension path has been identified and tested on Apple Silicon. The runtime proof must create a display visible to macOS, render a normal application into it, capture it, route input to it, and demonstrate that the primary display is not disturbed.

Until then, the protocol, host lifecycle, pairing, and iOS desktop shell can be developed independently, but the complete remote workspace is not claimed as working.

## Temporary VoidDisplay experiment

The user selected the open-source [VoidDisplay](https://github.com/iamsyc/VoidDisplay)
path for development. VoidDisplay uses the private `CGVirtualDisplay` runtime rather
than a supported Apple display-extension API. MACLand therefore keeps the private
declarations inside `MacHost/Sources/MACLandHost/VoidDisplayPrivate` and exposes only
a typed create/destroy adapter to the rest of the host.

This lets us test the actual display lifecycle on the target Mac while preserving the
public-API gate as failed. It does not satisfy the original production requirement:
private APIs can break across macOS releases, may be rejected by signing or review,
and must be replaced or quarantined before distribution.
