#!/bin/sh

set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT="$PROJECT_ROOT/MACLand.xcodeproj"
DERIVED_DATA_PATH=${MACLAND_DERIVED_DATA_PATH:-"$PROJECT_ROOT/.macland-derived-data"}
IOS_DEVICE_ID=${MACLAND_IOS_DEVICE_ID:-00008030-000E402C0291802E}
CORE_DEVICE_ID=${MACLAND_CORE_DEVICE_ID:-8568CEF4-6CB9-5C85-A02D-D21ED27101E7}
IOS_BUNDLE_ID=${MACLAND_IOS_BUNDLE_ID:-com.thraize.macland.mobile}
IOS_APP="$DERIVED_DATA_PATH/Build/Products/Debug-iphoneos/MACLandMobile.app"
HOST_APP="$DERIVED_DATA_PATH/Build/Products/Debug/MACLandHost.app"

echo $HOST_APP

XCODEBUILD=$(xcrun --find xcodebuild)

usage() {
    cat <<'EOF'
Usage:
  ./macland.sh "build host"
  ./macland.sh "build ios client"
  ./macland.sh "install ios client"
  ./macland.sh "open host"

Aliases:
  build-host, build-ios-client, install-ios-client, open-host

Environment overrides:
  MACLAND_IOS_DEVICE_ID       Xcode destination device ID
  MACLAND_CORE_DEVICE_ID      devicectl device ID
  MACLAND_DERIVED_DATA_PATH   Build output directory
EOF
}

generate_project() {
    if command -v xcodegen >/dev/null 2>&1; then
        (cd "$PROJECT_ROOT" && xcodegen generate >/dev/null)
    elif [ ! -d "$PROJECT" ]; then
        printf '%s\n' "xcodegen is required because MACLand.xcodeproj is not present." >&2
        exit 1
    fi
}

build_host() {
    generate_project
    "$XCODEBUILD" \
        -quiet \
        -project "$PROJECT" \
        -scheme MACLandHost \
        -sdk macosx \
        -configuration Debug \
        -derivedDataPath "$DERIVED_DATA_PATH" \
        CODE_SIGNING_ALLOWED=NO \
        build
}

build_ios_client() {
    generate_project
    if "$XCODEBUILD" \
        -quiet \
        -project "$PROJECT" \
        -scheme MACLandMobile \
        -configuration Debug \
        -destination "platform=iOS,id=$IOS_DEVICE_ID" \
        -derivedDataPath "$DERIVED_DATA_PATH" \
        -allowProvisioningUpdates \
        build; then
        return 0
    else
        status=$?
    fi

    printf '%s\n' "iOS build could not be signed." >&2
    printf '%s\n' "Open Xcode Settings > Accounts, re-authenticate the Apple ID for team UACGQ779PC, and ensure a development profile exists for $IOS_BUNDLE_ID." >&2
    return "$status"
}

install_ios_client() {
    build_ios_client
    xcrun devicectl device install app \
        --device "$CORE_DEVICE_ID" \
        "$IOS_APP"
}

open_host() {
    if [ ! -d "$HOST_APP" ]; then
        build_host
    fi
    open "$HOST_APP"
}

command_name=$*

case "$command_name" in
    "build host"|build-host)
        build_host
        ;;
    "build ios client"|build-ios-client)
        build_ios_client
        ;;
    "install ios client"|install-ios-client)
        install_ios_client
        ;;
    "open host"|open-host)
        open_host
        ;;
    help|--help|-h|"")
        usage
        ;;
    *)
        printf 'Unknown command: %s\n\n' "$command_name" >&2
        usage >&2
        exit 2
        ;;
esac
