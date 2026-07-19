#!/bin/zsh

set -euo pipefail

readonly LAUNCH_AGENT_TARGET="$HOME/Library/LaunchAgents/com.alvin.ios-portal.supervisor.plist"
readonly DOMAIN="gui/$(/usr/bin/id -u)"

/bin/launchctl bootout "$DOMAIN" "$LAUNCH_AGENT_TARGET" 2>/dev/null || true
print "Stopped the iOS portal launch agent. The plist, logs, build, and status files were retained."
