#!/bin/bash

# macSCP-Revived DMG Creator Script
# This script creates a distributable DMG installer for macSCP-Revived

set -e

APP_NAME="macSCP-Revived"
# Version comes from the latest v* git tag (e.g. v1.0.0 -> 1.0.0)
VERSION=$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null | sed 's/^v//')
if [ -z "${VERSION}" ]; then
    echo "❌ No v* git tag found. Create a tag first: git tag v1.0.0"
    exit 1
fi
DMG_NAME="${APP_NAME}-${VERSION}"
BUILD_DIR="build"
DMG_DIR="dmg-staging"
FINAL_DMG="${DMG_NAME}.dmg"

echo "🚀 Building ${APP_NAME} ${VERSION}..."

# Archive the app (Release build)
xcodebuild archive \
    -project macSCP.xcodeproj \
    -scheme macSCP \
    -configuration Release \
    -archivePath "${BUILD_DIR}/${APP_NAME}.xcarchive" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM="" \
    | xcpretty || xcodebuild archive \
    -project macSCP.xcodeproj \
    -scheme macSCP \
    -configuration Release \
    -archivePath "${BUILD_DIR}/${APP_NAME}.xcarchive" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM=""

echo "✅ Build complete!"

# Export the app
echo "📦 Exporting app..."
xcodebuild -exportArchive \
    -archivePath "${BUILD_DIR}/${APP_NAME}.xcarchive" \
    -exportPath "${BUILD_DIR}" \
    -exportOptionsPlist exportOptions.plist

# Create DMG staging directory
echo "🎨 Creating DMG staging area..."
rm -rf "${DMG_DIR}"
mkdir -p "${DMG_DIR}"

# Copy app to staging
cp -R "${BUILD_DIR}/${APP_NAME}.app" "${DMG_DIR}/"

# Create Applications symlink
ln -s /Applications "${DMG_DIR}/Applications"

# Create DMG
echo "💿 Creating DMG..."
rm -f "${FINAL_DMG}"
hdiutil create -volname "${APP_NAME}" \
    -srcfolder "${DMG_DIR}" \
    -ov -format UDZO \
    "${FINAL_DMG}"

echo "✨ DMG created successfully: ${FINAL_DMG}"
echo ""
echo "📍 Location: $(pwd)/${FINAL_DMG}"
echo "📦 Size: $(du -h "${FINAL_DMG}" | cut -f1)"

# EdDSA signing for Sparkle updates
echo ""
echo "🔐 Signing DMG for Sparkle updates..."
SIGN_UPDATE=$(find ~/Library/Developer/Xcode/DerivedData/macSCP-*/SourcePackages/artifacts/sparkle/Sparkle/bin -name sign_update 2>/dev/null | head -1)

if [ -n "${SIGN_UPDATE}" ]; then
    SIGNATURE_OUTPUT=$("${SIGN_UPDATE}" "${FINAL_DMG}")
    echo "✅ DMG signed successfully"
    echo ""
    echo "📋 Add the following to appcast.xml <enclosure> tag:"
    echo "${SIGNATURE_OUTPUT}"
    echo ""
    DMG_LENGTH=$(stat -f%z "${FINAL_DMG}")
    echo "length=\"${DMG_LENGTH}\""
else
    echo "⚠️  sign_update not found in DerivedData. Build the project in Xcode first to resolve Sparkle SPM package."
    echo "   Then run: find ~/Library/Developer/Xcode/DerivedData/macSCP-*/SourcePackages/artifacts/sparkle/Sparkle/bin -name sign_update"
fi

echo ""
echo "To install: Double-click the DMG and drag ${APP_NAME} to Applications folder"
