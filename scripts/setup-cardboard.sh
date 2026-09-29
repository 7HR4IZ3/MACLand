#!/bin/bash
# Build the official SDK and a private, generated XcodeGen overlay on a Mac.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
REVISION=5969239e7c87f4cd64c8ec170ce1e7f4eb559e37
CACHE="$ROOT/.cardboard-build"
SOURCE="$CACHE/source"
DEST="$ROOT/iOS/ThirdParty/Cardboard"
for tool in xcodebuild xcrun pod xcodegen git python3; do
    command -v "$tool" >/dev/null || { echo "Install $tool before running setup-cardboard.sh." >&2; exit 1; }
done
mkdir -p "$CACHE" "$DEST/Headers"
if [ ! -d "$SOURCE/.git" ]; then
    git clone https://github.com/googlevr/cardboard.git "$SOURCE"
fi
git -C "$SOURCE" fetch origin "$REVISION"
git -C "$SOURCE" checkout --detach "$REVISION"
(cd "$SOURCE" && pod install)
for SDK in iphoneos iphonesimulator; do
    DERIVED="$CACHE/$SDK"
    xcodebuild -workspace "$SOURCE/Cardboard.xcworkspace" -scheme sdk \
        -configuration Release -sdk "$SDK" -derivedDataPath "$DERIVED" \
        ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO build
    PRODUCTS="$DERIVED/Build/Products/Release-$SDK"
    CARDBOARD="$PRODUCTS/GfxPluginCardboard.a"
    PROTOBUF="$PRODUCTS/Protobuf-C++/libProtobuf-C++.a"
    test -f "$CARDBOARD" && test -f "$PROTOBUF"
    xcrun libtool -static -o "$CACHE/libCardboard-$SDK.a" "$CARDBOARD" "$PROTOBUF"
done
cp "$SOURCE/sdk/include/cardboard.h" "$DEST/Headers/cardboard.h"
# Replace only this script's generated framework, never user code.
rm -rf "$DEST/Cardboard.xcframework"
xcodebuild -create-xcframework \
    -library "$CACHE/libCardboard-iphoneos.a" -headers "$DEST/Headers" \
    -library "$CACHE/libCardboard-iphonesimulator.a" -headers "$DEST/Headers" \
    -output "$DEST/Cardboard.xcframework"
rm -rf "$DEST/sdk.bundle"
cp -R "$SOURCE/sdk/qrcode/ios/sdk.bundle" "$DEST/sdk.bundle"
cp "$SOURCE/LICENSE" "$DEST/LICENSE-Cardboard"
# CocoaPods includes the matching protobuf license in its source tree.
cp "$SOURCE/Pods/Protobuf-C++/LICENSE" "$DEST/LICENSE-Protobuf"
cat > "$ROOT/project.cardboard.yml" <<'YAML'
include:
  - project.yml
targets:
  MACLandMobile:
    sources:
      - path: iOS/ThirdParty/Cardboard/sdk.bundle
        buildPhase: resources
      - path: iOS/ThirdParty/Cardboard/LICENSE-Cardboard
        buildPhase: resources
      - path: iOS/ThirdParty/Cardboard/LICENSE-Protobuf
        buildPhase: resources
    dependencies:
      - framework: iOS/ThirdParty/Cardboard/Cardboard.xcframework
        embed: false
      - sdk: AVFoundation.framework
      - sdk: CoreMotion.framework
      - sdk: GLKit.framework
      - sdk: OpenGLES.framework
      - sdk: MetalKit.framework
    settings:
      base:
        HEADER_SEARCH_PATHS: "$(inherited) $(SRCROOT)/iOS/ThirdParty/Cardboard/Headers"
        GCC_PREPROCESSOR_DEFINITIONS: "$(inherited) MACLAND_CARDBOARD=1"
        OTHER_LDFLAGS: "$(inherited) -ObjC -lc++"
YAML
(cd "$ROOT" && xcodegen generate --spec project.cardboard.yml)
echo "Cardboard is configured. Build MACLandMobile, then scan the viewer QR code before entry."
