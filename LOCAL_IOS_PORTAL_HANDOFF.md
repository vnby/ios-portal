# Local iOS Portal Handoff

This document is for LLM agents working on Alvin's Mac with the iPhone 7 connected over USB.
Use it to start, verify, and stop the local `vnby/ios-portal` flow without asking for the same setup details again.

## Fixed Local Assumptions

| Item | Value |
| --- | --- |
| Repo path | `/Users/alvin/Documents/Personal/Dev/mobile/ios-portal` |
| Required Xcode | `/Applications/Xcode_26.2.app/Contents/Developer` |
| Connected device | `Alvin's iPhone 7`, iOS `15.8.7` |
| Device UDID | `52181a4873864c3323d52b4bc0c87d3068617f31` |
| Portal app bundle ID | `com.alvin.mobilerun-ios-portal` |
| Device server port | `6643` |
| Mac forwarded port | `16643` |
| Mac portal URL | `http://127.0.0.1:16643` |
| Launchd runner label | `local.ios-portal.runner` |
| Launchd iproxy label | `local.ios-portal.iproxy` |

The iPhone 7 is expected to stay connected. UI Automation has been enabled on the device. Use Xcode 26.2 explicitly; do not rely on the default `xcode-select` path because this Mac may also have another Xcode installed.

## Quick Health Check

First check whether the portal is already running:

```bash
curl -fsS http://127.0.0.1:16643/device/date
```

If this returns JSON, keep using the running server. You can also check the launchd jobs:

```bash
launchctl list | rg 'local\.ios-portal'
lsof -nP -iTCP:16643 -sTCP:LISTEN
```

## Start The Portal

Run these commands from any shell on the Mac:

```bash
cd /Users/alvin/Documents/Personal/Dev/mobile/ios-portal

launchctl remove local.ios-portal.runner 2>/dev/null || true
launchctl remove local.ios-portal.iproxy 2>/dev/null || true
lsof -tiTCP:16643 -sTCP:LISTEN | xargs -r kill

launchctl submit \
  -l local.ios-portal.runner \
  -o /tmp/ios-portal-device-xcodebuild.out \
  -e /tmp/ios-portal-device-xcodebuild.err \
  -- /bin/zsh -lc 'cd /Users/alvin/Documents/Personal/Dev/mobile/ios-portal && env DEVELOPER_DIR=/Applications/Xcode_26.2.app/Contents/Developer xcodebuild test -skipMacroValidation -allowProvisioningUpdates -allowProvisioningDeviceRegistration -project droidrun-ios-portal.xcodeproj -scheme droidrun-ios-portal -destination "platform=iOS,id=52181a4873864c3323d52b4bc0c87d3068617f31" "-only-testing:Droidrun Server/DroidrunPortalServer/testLoop"'

launchctl submit \
  -l local.ios-portal.iproxy \
  -o /tmp/ios-portal-iproxy.out \
  -e /tmp/ios-portal-iproxy.err \
  -- /opt/homebrew/bin/iproxy 16643 6643 -u 52181a4873864c3323d52b4bc0c87d3068617f31
```

Wait until the API responds:

```bash
for i in {1..90}; do
  if curl -fsS --max-time 3 http://127.0.0.1:16643/device/date; then
    echo
    break
  fi
  sleep 2
done
```

The XCTest process is intentionally long-running. It starts the HTTP server in test setup and keeps the run loop alive.

## Self-Test

Use these checks after starting the portal, or after code changes that affect the API:

```bash
curl -fsS http://127.0.0.1:16643/device/date

curl -fsS \
  -H 'Content-Type: application/json' \
  -d '{"bundleIdentifier":"com.alvin.mobilerun-ios-portal"}' \
  http://127.0.0.1:16643/inputs/launch

curl -fsS http://127.0.0.1:16643/state | head -c 1200

curl -fsS http://127.0.0.1:16643/vision/screenshot \
  -o /tmp/ios-portal-iphone7-screenshot.png

file /tmp/ios-portal-iphone7-screenshot.png
```

Expected signs of success:

- `/device/date` returns JSON with a `date`.
- `/inputs/launch` returns `{"message":"opened com.alvin.mobilerun-ios-portal"}`.
- `/state` shows the portal app, usually with `Welcome to Droidrun!`.
- The screenshot is a valid PNG. On this iPhone 7 it is normally `750 x 1334`.

## Foreground Alternative

If launchd is not appropriate, use two foreground terminals.

Terminal 1:

```bash
cd /Users/alvin/Documents/Personal/Dev/mobile/ios-portal
DEVELOPER_DIR=/Applications/Xcode_26.2.app/Contents/Developer \
  xcodebuild test \
  -skipMacroValidation \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  -project droidrun-ios-portal.xcodeproj \
  -scheme droidrun-ios-portal \
  -destination 'platform=iOS,id=52181a4873864c3323d52b4bc0c87d3068617f31' \
  '-only-testing:Droidrun Server/DroidrunPortalServer/testLoop'
```

Terminal 2:

```bash
/opt/homebrew/bin/iproxy 16643 6643 -u 52181a4873864c3323d52b4bc0c87d3068617f31
```

Then use `http://127.0.0.1:16643`.

## Stop The Portal

```bash
launchctl remove local.ios-portal.runner 2>/dev/null || true
launchctl remove local.ios-portal.iproxy 2>/dev/null || true
lsof -tiTCP:16643 -sTCP:LISTEN | xargs -r kill
```

If a foreground `xcodebuild test` is running, stop it with `Ctrl-C`. Xcode may report `TEST INTERRUPTED`; that is expected when stopping this long-running server.

## Troubleshooting

- `Macro "Plugins" ... must be enabled`: rerun with `-skipMacroValidation`.
- Provisioning profile errors: ensure Alvin is logged into the Apple Account in `Xcode_26.2.app`, then use `-allowProvisioningUpdates -allowProvisioningDeviceRegistration`.
- `Unknown build action 'Server/DroidrunPortalServer/testLoop'`: the `-only-testing` argument was split incorrectly. Quote the full argument exactly as `"-only-testing:Droidrun Server/DroidrunPortalServer/testLoop"`.
- `curl: Failed to connect` or `iproxy` says `Connection refused`: the XCTest server is not ready or has stopped. Check `/tmp/ios-portal-device-xcodebuild.err` and `/tmp/ios-portal-device-xcodebuild.out`, then restart both launchd jobs.
- Port conflict on `16643`: stop any old forwarder with `lsof -tiTCP:16643 -sTCP:LISTEN | xargs -r kill`.
- Device launch hangs: unlock the iPhone, confirm it trusts the Mac, and confirm UI Automation remains enabled.

## Build-Only Check

Use this when you only need to verify compilation/signing:

```bash
cd /Users/alvin/Documents/Personal/Dev/mobile/ios-portal
DEVELOPER_DIR=/Applications/Xcode_26.2.app/Contents/Developer \
  xcodebuild build \
  -skipMacroValidation \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  -project droidrun-ios-portal.xcodeproj \
  -scheme droidrun-ios-portal \
  -destination 'platform=iOS,id=52181a4873864c3323d52b4bc0c87d3068617f31'
```
