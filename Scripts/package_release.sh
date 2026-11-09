#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_DIR"

echo "==> 1. Building release application bundle..."
./Scripts/build_app.sh

echo "==> 2. Creating distribution zip archive..."
ZIP_NAME="WinVClipboard.app.zip"
rm -f "$ZIP_NAME" "$ZIP_NAME.sha256"

# Use ditto to preserve macOS metadata and resource forks cleanly
ditto -c -k --sequesterRsrc --keepParent WinVClipboard.app "$ZIP_NAME"
shasum -a 256 "$ZIP_NAME" > "$ZIP_NAME.sha256"

echo "==> 3. Creating distribution DMG disk image..."
DMG_NAME="WinVClipboard.dmg"
rm -f "$DMG_NAME" "$DMG_NAME.sha256"

DMG_STAGING_DIR="$(mktemp -d /tmp/winv_dmg_staging.XXXXXX)"
cp -R "WinVClipboard.app" "$DMG_STAGING_DIR/"
ln -s /Applications "$DMG_STAGING_DIR/Applications"

hdiutil create -volname "WinV Clipboard" -srcfolder "$DMG_STAGING_DIR" -ov -format UDZO "$DMG_NAME"
rm -rf "$DMG_STAGING_DIR"

shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256"

DMG_SIZE=$(du -h "$DMG_NAME" | awk '{print $1}')
DMG_SHA=$(cat "$DMG_NAME.sha256" | awk '{print $1}')

ZIP_SIZE=$(du -h "$ZIP_NAME" | awk '{print $1}')
ZIP_SHA=$(cat "$ZIP_NAME.sha256" | awk '{print $1}')

echo "=========================================================="
echo " Packaging Complete!"
echo " DMG (Installer):  $PROJECT_DIR/$DMG_NAME ($DMG_SIZE)"
echo "   SHA-256:        $DMG_SHA"
echo " ZIP (Auto-Update):$PROJECT_DIR/$ZIP_NAME ($ZIP_SIZE)"
echo "   SHA-256:        $ZIP_SHA"
echo "=========================================================="
echo ""
echo "Next steps to publish on GitHub:"
echo "1. Create a git tag:    git tag -a v1.0.0 -m \"Release v1.0.0\""
echo "2. Push the tag:        git push origin v1.0.0"
echo "3. Go to GitHub:        https://github.com/anujawitharana/clipbaord-for-mac/releases/new"
echo "4. Attach:              $DMG_NAME and $ZIP_NAME"
echo "5. Click Publish release!"
