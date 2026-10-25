#!/bin/bash
# Optional local distribution: Xcode archive/export, DMG, signing and notarization.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to an existing notarytool Keychain profile.}"
IDENTITY="${SIGNING_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  identities="$(security find-identity -v -p codesigning | awk -F '"' '/Developer ID Application:/ {print $2}')"
  count="$(printf '%s\n' "$identities" | awk 'NF {n++} END {print n+0}')"
  [[ "$count" == 1 ]] || { echo 'Set SIGNING_IDENTITY to one full Developer ID Application certificate name.' >&2; exit 1; }
  IDENTITY="$identities"
fi
TEAM="${DEVELOPMENT_TEAM:-$(printf '%s\n' "$IDENTITY" | sed -n 's/.*(\([A-Z0-9]\{10\}\))$/\1/p')}"
[[ -n "$TEAM" ]] || { echo 'Set DEVELOPMENT_TEAM to your Apple Developer Team ID.' >&2; exit 1; }
VERSION="$(awk '/^MARKETING_VERSION[[:space:]]*=/ {print $3; exit}' "$ROOT/Config/Weft.xcconfig")"
BUILD="$(awk '/^CURRENT_PROJECT_VERSION[[:space:]]*=/ {print $3; exit}' "$ROOT/Config/Weft.xcconfig")"
OUTPUT="$ROOT/local/outputs/releases/$VERSION-$BUILD"
[[ ! -e "$OUTPUT" ]] || { echo "Output already exists: $OUTPUT" >&2; exit 1; }
# Validate the local credentials before compiling; never export them.
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" --output-format json >/dev/null
mkdir -p "$OUTPUT"
OPTIONS="$OUTPUT/ExportOptions.plist"
cp "$ROOT/Config/ExportOptions.plist" "$OPTIONS"
plutil -replace teamID -string "$TEAM" "$OPTIONS"
xcodebuild -project "$ROOT/Weft.xcodeproj" -scheme Weft -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$ROOT/local/outputs/DerivedData" \
  -archivePath "$OUTPUT/weft.xcarchive" DEVELOPMENT_TEAM="$TEAM" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" archive
xcodebuild -exportArchive -archivePath "$OUTPUT/weft.xcarchive" \
  -exportPath "$OUTPUT/export" -exportOptionsPlist "$OPTIONS"
APP="$OUTPUT/export/weft.app"
codesign --verify --deep --strict "$APP"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/weft-dmg.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/weft.app"
ln -s /Applications "$STAGING/Applications"
DMG="$OUTPUT/weft-$VERSION-universal.dmg"
hdiutil create -volname weft -srcfolder "$STAGING" -fs HFS+ -format UDZO "$DMG"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"
codesign --verify --strict "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait --timeout 10m
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
hdiutil verify "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
(cd "$OUTPUT" && shasum -a 256 "${DMG##*/}" > "${DMG##*/}.sha256")
printf 'Signed and notarized DMG: %s\n' "$DMG"
