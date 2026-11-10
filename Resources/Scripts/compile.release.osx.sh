#!/bin/bash

set -euo pipefail

SRCROOT=$(realpath "$1")
TARGET_ZIP=$2

WORKSPACE="$SRCROOT/Asspp.xcworkspace"
SCHEME="Asspp"
BUILD_PRODUCT="Asspp.app"

cd "$SRCROOT"
store_packaging_dir=$(mktemp -d)
store_developer_config="$SRCROOT/Configuration/Developer.xcconfig"
if [ -f "$store_developer_config" ]; then
    cp "$store_developer_config" "$store_packaging_dir/Developer.xcconfig"
fi
store_restore_config() {
    if [ -f "$store_packaging_dir/Developer.xcconfig" ]; then
        cp "$store_packaging_dir/Developer.xcconfig" "$store_developer_config"
    else
        rm -f "$store_developer_config"
    fi
    rm -rf "$store_packaging_dir"
}
trap store_restore_config EXIT

# Temporarily disable signing without replacing the developer's configuration.
cat >"$SRCROOT/Configuration/Developer.xcconfig" <<'EOF'
// CI-generated Developer.xcconfig
// Code signing is completely disabled for CI builds
DEVELOPMENT_TEAM =
CODE_SIGN_STYLE = Manual
CODE_SIGN_IDENTITY =
CODE_SIGN_IDENTITY[sdk=macosx*] =
CODE_SIGNING_REQUIRED = NO
CODE_SIGNING_ALLOWED = NO
EOF

xcodebuild -workspace "$WORKSPACE" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$SRCROOT/build/DerivedDataApp" \
    -destination 'generic/platform=macOS' \
    build \
    ARCHS=arm64 ONLY_ACTIVE_ARCH=YES ENABLE_USER_SCRIPT_SANDBOXING=NO \
    DEVELOPMENT_TEAM="" CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGN_ENTITLEMENTS="" CODE_SIGNING_ALLOWED="NO" \
    GCC_GENERATE_DEBUGGING_SYMBOLS=YES STRIP_INSTALLED_PRODUCT=NO \
    COPY_PHASE_STRIP=NO UNSTRIPPED_PRODUCT=NO \
    | xcbeautify

BUILD_PRODUCT_PATH="$SRCROOT/build/DerivedDataApp/Build/Products/Release/$BUILD_PRODUCT"
if [ ! -d "$BUILD_PRODUCT_PATH" ]; then
    echo "[-] build product not found"
    exit 1
fi

echo "[+] build product path: $BUILD_PRODUCT_PATH"

codesign --force --deep --sign - --timestamp=none "$BUILD_PRODUCT_PATH"

echo "[+] packaging..."
pushd "$SRCROOT/build/DerivedDataApp/Build/Products/Release"
zip -q -r -y "$store_packaging_dir/Asspp.zip" "$BUILD_PRODUCT"
popd
mv "$store_packaging_dir/Asspp.zip" "$TARGET_ZIP"

echo "[+] done"
