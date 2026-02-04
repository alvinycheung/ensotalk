#!/bin/bash
set -e

echo "🎙️ EnsoTalk Installer"
echo "===================="
echo ""

# Check macOS version
OS_VERSION=$(sw_vers -productVersion | cut -d. -f1)
if [ "$OS_VERSION" -lt 14 ]; then
    echo "❌ Error: macOS 14+ required (you have $(sw_vers -productVersion))"
    exit 1
fi

# Check for Swift
if ! command -v swift &> /dev/null; then
    echo "❌ Error: Swift not found. Install Xcode Command Line Tools:"
    echo "   xcode-select --install"
    exit 1
fi

echo "✓ macOS $(sw_vers -productVersion)"
echo "✓ Swift $(swift --version 2>&1 | head -1 | awk '{print $3}')"
echo ""

# Check OpenClaw config
OPENCLAW_CONFIG="$HOME/.openclaw/openclaw.json"
if [ ! -f "$OPENCLAW_CONFIG" ]; then
    echo "❌ Error: OpenClaw config not found at $OPENCLAW_CONFIG"
    echo "   Make sure OpenClaw is installed and configured."
    exit 1
fi

# Check for chat completions endpoint
if ! grep -q '"chatCompletions"' "$OPENCLAW_CONFIG"; then
    echo "⚠️  Warning: Chat completions endpoint may not be enabled."
    echo "   Add this to your config:"
    echo '   "gateway": { "http": { "endpoints": { "chatCompletions": { "enabled": true } } } }'
    echo ""
fi

echo "Building EnsoTalk..."
swift build -c release 2>&1 | tail -5

echo ""
echo "Creating app bundle..."
./bundle.sh

echo ""
echo "Installing to /Applications..."
if [ -d "/Applications/EnsoTalk.app" ]; then
    echo "   Removing existing installation..."
    rm -rf "/Applications/EnsoTalk.app"
fi
cp -r .build/EnsoTalk.app /Applications/

echo ""
echo "✅ EnsoTalk installed successfully!"
echo ""
echo "To start: open /Applications/EnsoTalk.app"
echo "Or run:   open -a EnsoTalk"
echo ""
echo "📝 First time setup:"
echo "   1. Grant microphone permission when prompted"
echo "   2. Click the waveform icon in menu bar"
echo "   3. Choose 'Push to Talk' or 'Always Listening'"
echo "   4. Press ⌥Space (or just speak in always-listening mode)"
echo ""
echo "🐯 Built by EnsoPrime"
