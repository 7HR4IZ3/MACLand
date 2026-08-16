#!/usr/bin/env bash
set -euo pipefail

sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
core_graphics_headers="$sdk_path/System/Library/Frameworks/CoreGraphics.framework/Headers"

if [[ ! -d "$core_graphics_headers" ]]; then
  printf 'Virtual display gate: blocked; CoreGraphics public headers were not found at %s\n' "$core_graphics_headers" >&2
  exit 2
fi

if ! rg -q -i 'CGVirtualDisplay|VirtualDisplayDescriptor|VirtualDisplaySettings' "$core_graphics_headers"; then
  printf 'Virtual display gate: blocked; the macOS SDK exposes no matching public CoreGraphics virtual-display declarations.\n' >&2
  exit 2
fi

printf 'Virtual display gate: declarations found in the public SDK. A signed runtime proof is still required.\n'
