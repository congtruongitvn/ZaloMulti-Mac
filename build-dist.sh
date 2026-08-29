#!/bin/bash
# build-dist.sh — Build script tạo phiên bản đóng gói cho tất cả chip Apple
# Sử dụng: bash build-dist.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
DIST_DIR="$PROJECT_DIR/dist"
PROJECT="$PROJECT_DIR/ZaloMulti.xcodeproj"
SCHEME="ZaloMulti"
VERSION=$(grep -m1 "MARKETING_VERSION" "$PROJECT/project.pbxproj" | grep -o '[0-9]\+\.[0-9]\+\.[0-9]*' | head -1)

echo "╔══════════════════════════════════════════════════════╗"
echo "║  ZaloMulti Build Script — v${VERSION:-2.1.0}                  ║"
echo "║  Tạo bản đóng gói cho Intel + Apple Silicon         ║"
echo "╚══════════════════════════════════════════════════════╝"

# Cleanup
echo ""
echo "▸ Dọn dẹp..."
pkill -f ZaloMulti 2>/dev/null || true
pkill -9 -f xcodebuild 2>/dev/null || true
sleep 1
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

build_arch() {
    local ARCH=$1
    local LABEL=$2
    local BUILD_DIR="$DIST_DIR/build-$LABEL"
    
    echo ""
    echo "═══════════════════════════════════════════════════"
    echo "  Building: $LABEL ($ARCH) — Configuration: Release"
    echo "═══════════════════════════════════════════════════"
    
    # Mỗi arch dùng SYMROOT riêng + OBJROOT riêng + derivedDataPath riêng trong workspace
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
        -configuration Release \
        ARCHS="$ARCH" \
        ONLY_ACTIVE_ARCH=NO \
        SWIFT_OPTIMIZATION_LEVEL="-O" \
        GCC_OPTIMIZATION_LEVEL=s \
        SYMROOT="$BUILD_DIR" \
        OBJROOT="$BUILD_DIR/obj" \
        -derivedDataPath "$BUILD_DIR/derived" \
        build 2>&1 | grep -E "^.*(error:|BUILD FAILED|BUILD SUCCEEDED)" || true
    
    # Kiểm tra build result
    local APP_PATH=$(find "$BUILD_DIR" -name "ZaloMulti.app" -type d | grep -v "/derived/" | head -n 1)
    if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
        APP_PATH=$(find "$BUILD_DIR" -name "ZaloMulti.app" -type d | head -n 1)
    fi
    
    if [ -z "$APP_PATH" ] || [ ! -f "$APP_PATH/Contents/MacOS/ZaloMulti" ]; then
        echo "❌ Build failed — no binary for $ARCH in $BUILD_DIR"
        return 1
    fi
    
    # Strip debug symbols
    strip -x "$APP_PATH/Contents/MacOS/ZaloMulti" 2>/dev/null || true
    
    # Remove debug dylibs
    rm -f "$APP_PATH/Contents/MacOS/ZaloMulti.debug.dylib" 2>/dev/null
    rm -f "$APP_PATH/Contents/MacOS/__preview.dylib" 2>/dev/null
    
    local ENT_PATH="$PROJECT_DIR/ZaloMulti/Resources/ZaloCloneManager.entitlements"
    
    # Ad-hoc sign với entitlements cho Apple Silicon & Intel
    if [ -f "$ENT_PATH" ]; then
        codesign --force --sign - --entitlements "$ENT_PATH" --deep "$APP_PATH" 2>/dev/null || true
    else
        codesign --force --sign - --deep "$APP_PATH" 2>/dev/null || true
    fi
    
    # Copy to dist
    local FINAL_NAME="ZaloMulti-${VERSION:-2.1.0}-$LABEL.app"
    cp -R "$APP_PATH" "$DIST_DIR/$FINAL_NAME"
    
    local ARCH_INFO=$(file -b "$DIST_DIR/$FINAL_NAME/Contents/MacOS/ZaloMulti")
    echo "✅ $FINAL_NAME — $ARCH_INFO"
    
    # Tạo DMG
    local DMG_NAME="ZaloMulti-${VERSION:-2.1.0}-$LABEL.dmg"
    hdiutil create -volname "ZaloMulti" -srcfolder "$DIST_DIR/$FINAL_NAME" \
        -ov -format UDZO "$DIST_DIR/$DMG_NAME" 2>/dev/null
    
    if [ -f "$DIST_DIR/$DMG_NAME" ]; then
        local SIZE=$(du -h "$DIST_DIR/$DMG_NAME" | awk '{print $1}')
        echo "📦 $DMG_NAME ($SIZE)"
    fi
}

# ═══ BUILD 1: Intel (x86_64) ═══
build_arch "x86_64" "Intel"

# ═══ BUILD 2: Apple Silicon (arm64) ═══
build_arch "arm64" "AppleSilicon"

# ═══ BUILD 3: Universal (x86_64 + arm64) ═══
echo ""
echo "═══════════════════════════════════════════════════"
echo "  Building: Universal Binary (Intel + Apple Silicon)"
echo "═══════════════════════════════════════════════════"

INTEL_BIN="$DIST_DIR/ZaloMulti-${VERSION:-2.1.0}-Intel.app/Contents/MacOS/ZaloMulti"
ARM_BIN="$DIST_DIR/ZaloMulti-${VERSION:-2.1.0}-AppleSilicon.app/Contents/MacOS/ZaloMulti"

if [ -f "$INTEL_BIN" ] && [ -f "$ARM_BIN" ]; then
    UNIVERSAL_APP="$DIST_DIR/ZaloMulti-${VERSION:-2.1.0}-Universal.app"
    cp -R "$DIST_DIR/ZaloMulti-${VERSION:-2.1.0}-Intel.app" "$UNIVERSAL_APP"
    
    # Merge với lipo
    lipo -create "$INTEL_BIN" "$ARM_BIN" -output "$UNIVERSAL_APP/Contents/MacOS/ZaloMulti"
    
    # Re-sign
    ENT_PATH="$PROJECT_DIR/ZaloMulti/Resources/ZaloCloneManager.entitlements"
    if [ -f "$ENT_PATH" ]; then
        codesign --force --sign - --entitlements "$ENT_PATH" --deep "$UNIVERSAL_APP" 2>/dev/null || true
    else
        codesign --force --sign - --deep "$UNIVERSAL_APP" 2>/dev/null || true
    fi
    
    echo "✅ $(file -b "$UNIVERSAL_APP/Contents/MacOS/ZaloMulti")"
    
    # DMG
    DMG_NAME="ZaloMulti-${VERSION:-2.1.0}-Universal.dmg"
    hdiutil create -volname "ZaloMulti" -srcfolder "$UNIVERSAL_APP" \
        -ov -format UDZO "$DIST_DIR/$DMG_NAME" 2>/dev/null
    
    if [ -f "$DIST_DIR/$DMG_NAME" ]; then
        SIZE=$(du -h "$DIST_DIR/$DMG_NAME" | awk '{print $1}')
        echo "📦 $DMG_NAME ($SIZE)"
    fi
else
    echo "⚠️  Không thể tạo Universal — thiếu binary"
    [ ! -f "$INTEL_BIN" ] && echo "   Missing: Intel binary"
    [ ! -f "$ARM_BIN" ] && echo "   Missing: Apple Silicon binary"
fi

# Cleanup build dirs
rm -rf "$DIST_DIR/build-Intel" "$DIST_DIR/build-AppleSilicon"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  KẾT QUẢ ĐÓNG GÓI                                  ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

for dmg in "$DIST_DIR"/ZaloMulti-*-*.dmg; do
    [ -f "$dmg" ] && echo "  📦 $(basename $dmg) — $(du -h "$dmg" | awk '{print $1}')"
done

echo ""
echo "  Tương thích:"
echo "  ┌──────────────────────┬──────────────────────────────────────────┐"
echo "  │ Intel.dmg            │ MacBook Pro/Air/iMac (2012-2020)        │"
echo "  │                      │ Chip Intel Core i3/i5/i7/i9             │"
echo "  ├──────────────────────┼──────────────────────────────────────────┤"
echo "  │ AppleSilicon.dmg     │ MacBook Pro/Air/iMac (2020+)            │"
echo "  │                      │ Chip M1/M1 Pro/Max/Ultra                │"
echo "  │                      │ Chip M2/M2 Pro/Max/Ultra                │"
echo "  │                      │ Chip M3/M3 Pro/Max/Ultra                │"
echo "  │                      │ Chip M4/M4 Pro/Max/Ultra                │"
echo "  ├──────────────────────┼──────────────────────────────────────────┤"
echo "  │ Universal.dmg        │ TẤT CẢ máy Mac (khuyến nghị)           │"
echo "  └──────────────────────┴──────────────────────────────────────────┘"
echo ""
echo "Done! Files: $DIST_DIR"
