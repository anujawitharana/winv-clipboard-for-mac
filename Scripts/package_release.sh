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

echo "==> 3. Generating SHA256 checksum..."
shasum -a 256 "$ZIP_NAME" > "$ZIP_NAME.sha256"

CHECKSUM=$(cat "$ZIP_NAME.sha256" | awk '{print $1}')
FILE_SIZE=$(du -h "$ZIP_NAME" | awk '{print $1}')

echo "=========================================================="
echo " Packaging Complete!"
echo " File:      $PROJECT_DIR/$ZIP_NAME ($FILE_SIZE)"
echo " SHA-256:   $CHECKSUM"
echo "=========================================================="
echo ""
echo "Next steps to publish on GitHub:"
echo "1. Create a git tag:    git tag -a v1.0.0 -m \"Release v1.0.0\""
echo "2. Push the tag:        git push origin v1.0.0"
echo "3. Go to GitHub:        https://github.com/anujawitharana/clipbaord-for-mac/releases/new"
echo "4. Attach:              $ZIP_NAME and $ZIP_NAME.sha256"
echo "5. Click Publish release!"
