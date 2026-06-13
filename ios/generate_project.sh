#!/usr/bin/env bash
set -e

# Generates HeartRate.xcodeproj from project.yml using XcodeGen.
# XcodeGen is the canonical way to manage Xcode projects in source control.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "→ Checking for XcodeGen..."

if command -v xcodegen &> /dev/null; then
    echo "  XcodeGen found at $(which xcodegen)"
else
    echo "  XcodeGen not found. Installing via Homebrew..."
    if ! command -v brew &> /dev/null; then
        echo "ERROR: Homebrew not installed. Install it from https://brew.sh then re-run."
        exit 1
    fi
    brew install xcodegen
fi

echo "→ Generating HeartRate.xcodeproj..."
xcodegen generate --spec project.yml

echo "→ Done! Open with:"
echo "   open HeartRate.xcodeproj"
echo ""
echo "→ To run tests from the command line (requires Xcode):"
echo "   xcodebuild test -project HeartRate.xcodeproj -scheme HeartRate -destination 'platform=iOS Simulator,name=iPhone 16'"
