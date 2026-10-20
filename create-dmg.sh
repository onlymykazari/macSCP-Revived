#!/bin/bash

# macSCP-Revived DMG Creator Script
# This script creates a distributable DMG installer for macSCP-Revived

set -e

APP_NAME="macSCP-Revived"
# Base version comes from the latest v* git tag (e.g. v1.0.0 -> 1.0.0).
# Local builds are distinguishable from release builds: when there are
# commits after the tag or uncommitted changes, the version gets a
# suffix like 1.0.1-dev.3.g1a2b3c.dirty
TAG=$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null | sed 's/^v//')
if [ -z "${TAG}" ]; then
    echo "❌ No v* git tag found. Create a tag first: git tag v1.0.0"
    exit 1
fi
SINCE_TAG=$(git rev-list --count "v${TAG}..HEAD" 2>/dev/null || echo 0)
SHORT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
if git diff --quiet >/dev/null 2>&1 && git diff --cached --quiet >/dev/null 2>&1 && [ "${SINCE_TAG}" = "0" ]; then
    VERSION="${TAG}"
else
    # dirty builds also get a build timestamp so every package name is unique
    VERSION="${TAG}-dev.${SINCE_TAG}.g${SHORT_SHA}$(git status --porcelain 2>/dev/null | grep -q . && echo ".dirty.$(date +%H%M%S)")"
fi
BUILD_NUMBER=$(git rev-list --count HEAD 2>/dev/null || echo 0)
echo "🏷️  Version: ${VERSION} (build ${BUILD_NUMBER})"
DMG_NAME="${APP_NAME}-${VERSION}"
BUILD_DIR="build"
DMG_DIR="dmg-staging"
FINAL_DMG="${DMG_NAME}.dmg"

echo "🚀 Building ${APP_NAME} ${VERSION}..."

# Archive the app (Release build); env vars override the Stamp Version phase
xcodebuild archive \
    -project macSCP.xcodeproj \
    -scheme macSCP \
    -configuration Release \
    -archivePath "${BUILD_DIR}/${APP_NAME}.xcarchive" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM="" \
    MACSCP_VERSION="${VERSION}" \
    MACSCP_BUILD_NUMBER="${BUILD_NUMBER}" \
    | xcpretty || MACSCP_VERSION="${VERSION}" MACSCP_BUILD_NUMBER="${BUILD_NUMBER}" xcodebuild archive \
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

# Stamp the exported app's version explicitly. The build-phase stamp does not
# reliably land on the exported copy; touching Info.plist invalidates the
# signature, so the app is re-signed (ad-hoc) right after.
#
# Re-signing MUST carry the entitlements forward: a bare `codesign --force`
# drops them all (no sandbox, no file access). Xcode also strips the
# app-scoped-bookmarks entitlement under ad-hoc signing, so it is added back
# here — it keeps private-key folder grants valid across launches.
EXPORTED_APP="${BUILD_DIR}/${APP_NAME}.app"
EXPORTED_PLIST="${EXPORTED_APP}/Contents/Info.plist"
ENTITLEMENTS_TMP="${BUILD_DIR}/resign-entitlements.plist"
# Entitlements come from the project file; the keychain access group needs a
# team identifier, which ad-hoc signing does not have.
cp macSCP/macSCP.entitlements "${ENTITLEMENTS_TMP}"
/usr/libexec/PlistBuddy -c "Delete :keychain-access-groups" "${ENTITLEMENTS_TMP}" 2>/dev/null || true

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${EXPORTED_PLIST}"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "${EXPORTED_PLIST}"
codesign --force --sign - --timestamp=none --entitlements "${ENTITLEMENTS_TMP}" "${EXPORTED_APP}"
echo "🔖 Stamped version ${VERSION} (build ${BUILD_NUMBER})"

# Guard: the re-signed app must still be sandboxed with its entitlements
if ! codesign -d --entitlements - "${EXPORTED_APP}" 2>/dev/null | grep -a -q "com.apple.security.app-sandbox"; then
    echo "❌ Re-signed app lost its entitlements — aborting"
    exit 1
fi
echo "🔐 Entitlements preserved (sandbox + app-scoped bookmarks)"

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
