#!/bin/bash
# Downloads DM Sans and DM Mono fonts from Google Fonts CDN
# Run once: bash scripts/download_fonts.sh

set -e
FONTS_DIR="assets/fonts"
mkdir -p "$FONTS_DIR"

echo "Downloading DM Sans..."
curl -sL "https://fonts.gstatic.com/s/dmsans/v15/rP2Yp2ywxg089UriI5-g4vlH9VoD8Cmcqbu6-K6z9mXgjU0.woff2" -o /tmp/dmsans.zip || true

# Use Google Fonts API to download static TTF files
BASE="https://fonts.gstatic.com/s/dmsans/v15"

declare -A FILES=(
  ["DMSans-Regular.ttf"]="rP2Rp2ywxg089UriCZOIHQ.ttf"
  ["DMSans-Medium.ttf"]="rP2Rp2ywxg089UriCWCIHQ.ttf"
  ["DMSans-SemiBold.ttf"]="rP2Rp2ywxg089UriCXaIHQ.ttf"
  ["DMSans-Bold.ttf"]="rP2Rp2ywxg089UriCXiIHQ.ttf"
)

# Better approach: use static download from official Google Fonts zip
echo "Downloading from Google Fonts..."
curl -sL "https://fonts.google.com/download?family=DM+Sans" -o /tmp/dmsans_dl.zip
curl -sL "https://fonts.google.com/download?family=DM+Mono" -o /tmp/dmmono_dl.zip

cd /tmp
unzip -o dmsans_dl.zip -d dmsans_extracted 2>/dev/null || true
unzip -o dmmono_dl.zip -d dmmono_extracted 2>/dev/null || true

# Copy the weight files we need
PROJ_DIR="$(dirname "$0")/.."
FONTS_TARGET="$PROJ_DIR/assets/fonts"

find /tmp/dmsans_extracted -name "*Regular*.ttf"  | head -1 | xargs -I{} cp {} "$FONTS_TARGET/DMSans-Regular.ttf"  2>/dev/null || true
find /tmp/dmsans_extracted -name "*Medium*.ttf"   | head -1 | xargs -I{} cp {} "$FONTS_TARGET/DMSans-Medium.ttf"   2>/dev/null || true
find /tmp/dmsans_extracted -name "*SemiBold*.ttf" | head -1 | xargs -I{} cp {} "$FONTS_TARGET/DMSans-SemiBold.ttf" 2>/dev/null || true
find /tmp/dmsans_extracted -name "*Bold*.ttf"     | grep -v Italic | grep -v SemiBold | head -1 | xargs -I{} cp {} "$FONTS_TARGET/DMSans-Bold.ttf" 2>/dev/null || true
find /tmp/dmmono_extracted -name "*Regular*.ttf"  | head -1 | xargs -I{} cp {} "$FONTS_TARGET/DMMono-Regular.ttf"  2>/dev/null || true

echo "Fonts downloaded to assets/fonts/:"
ls -la "$FONTS_TARGET/"
