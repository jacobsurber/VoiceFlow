#!/bin/bash
#
# reset-accessibility.sh
# Resets and re-grants Whisp privacy permissions after a rebuild
#

set -e

BUNDLE_ID="com.whisp.app"
APP_PATH="/Applications/Whisp.app"

echo "🔧 Whisp Privacy Permission Reset"
echo "====================================="
echo ""

# Check if app exists
if [ ! -d "$APP_PATH" ]; then
    echo "❌ Whisp not found at $APP_PATH"
    echo "   Run 'make install' first"
    exit 1
fi

echo "📍 Found Whisp at: $APP_PATH"
echo "🆔 Bundle ID: $BUNDLE_ID"
echo ""

# Step 1: Quit Whisp
echo "1️⃣  Quitting Whisp..."
pkill -x Whisp 2>/dev/null && sleep 1 || echo "   (Whisp was not running)"

# Step 2: Try to reset TCC database (best effort)
echo ""
echo "2️⃣  Attempting to reset Whisp privacy permissions..."

reset_service() {
    local service="$1"
    if tccutil reset "$service" "$BUNDLE_ID" 2>/dev/null; then
        echo "   ✅ Reset $service"
    else
        echo "   ⚠️  Could not reset $service automatically"
    fi
}

reset_service Microphone
reset_service Accessibility
reset_service ListenEvent

# Step 3: Launch Whisp
echo ""
echo "3️⃣  Launching Whisp..."
open "$APP_PATH"
sleep 2

# Step 4: Instructions for re-granting permission
echo ""
echo "4️⃣  Now re-grant permissions as needed:"
echo ""
echo "   • Microphone: try recording once and click Allow"
echo "   • Accessibility: System Settings → Privacy & Security → Accessibility"
echo "   • Input Monitoring: System Settings → Privacy & Security → Input Monitoring"
echo "   • If old Whisp entries remain, remove them before re-adding /Applications/Whisp.app"
echo ""
echo "5️⃣  Test Whisp:"
echo ""
echo "   • Open Notes or TextEdit"
echo "   • Click in a text field"
echo "   • Try your normal recording trigger"
echo "   • Speak something (e.g., 'Testing smart paste')"
echo "   • Release the key or stop recording"
echo "   • Text should auto-paste after transcription"
echo ""
echo "✅ Script complete! Follow the steps above to finish setup."
