#!/bin/bash
set -e

# Whisp Build and Install Script
# This script builds Whisp and installs it to /Applications/

echo "🎙️  Building Whisp..."

# Get the project directory (parent of scripts/)
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

source "$PROJECT_DIR/scripts/signing-common.sh"

"$PROJECT_DIR/scripts/build.sh"

if [ ! -d "Whisp.app" ]; then
    echo "❌ Build failed - Whisp.app not found"
    exit 1
fi

# Kill running instance
echo "🛑 Stopping any running instances..."
pkill -x Whisp 2>/dev/null || true
sleep 1

# Install to Applications
echo "📲 Installing to /Applications/..."
rm -rf /Applications/Whisp.app
cp -R Whisp.app /Applications/

SIGNATURE_KIND="$(whisp_signature_kind /Applications/Whisp.app)"

echo ""
echo "✅ Whisp successfully installed to /Applications/Whisp.app"
echo ""
if [ "$SIGNATURE_KIND" = "stable" ]; then
    echo "✅ Stable code signing detected. Existing Microphone, Accessibility, and Input Monitoring permissions should persist across reinstalls."
else
    echo "⚠️  Installed app is not stably signed ($SIGNATURE_KIND). macOS privacy permissions can reset after each install."
    echo "⚠️  Re-grant these permissions if Whisp stops working after a rebuild:"
    echo "   1. System Settings → Privacy & Security → Microphone"
    echo "   2. System Settings → Privacy & Security → Accessibility"
    echo "   3. System Settings → Privacy & Security → Input Monitoring"
    echo ""
    echo "💡 To avoid this during development, run 'make setup-local-signing' once, then reinstall Whisp."
fi
echo ""
echo "🚀 Launch Whisp with: open /Applications/Whisp.app"
