#!/bin/zsh

set -euo pipefail

readonly REPO_DIR="/Users/alvin/Documents/Personal/Dev/mobile/ios-portal"
readonly DEVELOPER_DIR="/Applications/Xcode_26.2.app/Contents/Developer"
readonly DEVICE_UDID="52181a4873864c3323d52b4bc0c87d3068617f31"
readonly DERIVED_DATA_DIR="$HOME/Library/Developer/ios-portal/DerivedData"
readonly LOG_DIR="$HOME/Library/Logs/ios-portal"
readonly LAUNCH_AGENT_SOURCE="$REPO_DIR/support/com.alvin.ios-portal.supervisor.plist"
readonly LAUNCH_AGENT_TARGET="$HOME/Library/LaunchAgents/com.alvin.ios-portal.supervisor.plist"
readonly DOMAIN="gui/$(/usr/bin/id -u)"
readonly SERVICE="$DOMAIN/com.alvin.ios-portal.supervisor"

mkdir -p "$DERIVED_DATA_DIR" "$LOG_DIR" "$HOME/Library/LaunchAgents"

print "Building and signing the physical-device test bundle with Xcode 26.2..."
cd "$REPO_DIR"
/usr/bin/caffeinate -is /usr/bin/env DEVELOPER_DIR="$DEVELOPER_DIR" \
    "$DEVELOPER_DIR/usr/bin/xcodebuild" build-for-testing \
    -skipMacroValidation \
    -allowProvisioningUpdates \
    -allowProvisioningDeviceRegistration \
    -project droidrun-ios-portal.xcodeproj \
    -scheme droidrun-ios-portal \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    -destination "platform=iOS,id=$DEVICE_UDID" \
    -parallel-testing-enabled NO \
    | /usr/bin/tee "$LOG_DIR/build-for-testing.log"

print "Installing the launch agent..."
/bin/launchctl bootout "$DOMAIN" "$LAUNCH_AGENT_TARGET" 2>/dev/null || true
/usr/bin/install -m 0644 "$LAUNCH_AGENT_SOURCE" "$LAUNCH_AGENT_TARGET"
/bin/launchctl enable "$SERVICE"
/bin/launchctl bootstrap "$DOMAIN" "$LAUNCH_AGENT_TARGET"

print "Installed. Status: $HOME/Library/Application Support/ios-portal/status.json"
