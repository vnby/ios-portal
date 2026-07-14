# Local iOS Portal Handoff

This document is for LLM agents working on Alvin's Mac with the iPhone 7 connected over USB.
Use it to start, verify, and stop the local `vnby/ios-portal` flow without asking for the same setup details again.

## Fixed Local Assumptions

| Item | Value |
| --- | --- |
| Repo path | `/Users/alvin/Documents/Personal/Dev/mobile/ios-portal` |
| Required Xcode | `/Applications/Xcode_26.2.app/Contents/Developer` |
| Connected device | `Alvin's iPhone 7`, iOS `15.8.8` |
| Device UDID | `52181a4873864c3323d52b4bc0c87d3068617f31` |
| Portal app bundle ID | `com.alvin.mobilerun-ios-portal` |
| Device server port | `6643` |
| Mac forwarded port | `16643` |
| Mac portal URL | `http://127.0.0.1:16643` |
| Launchd runner label | `local.ios-portal.runner` |
| Launchd iproxy label | `local.ios-portal.iproxy` |

The iPhone 7 is expected to stay connected. UI Automation has been enabled before, but do not assume an unattended device can approve a new `Enable UI Automation` prompt. Use Xcode 26.2 explicitly; do not rely on the default `xcode-select` path because this Mac may also have another Xcode installed.

## Unattended Device Safety Rule

Before starting or restarting the XCTest portal, confirm that Alvin currently has physical access to the iPhone. Starting `xcodebuild test`, WebDriverAgent, XCUITest, or the portal runner can present an iPhone prompt that requires physical confirmation.

If Alvin does not have physical access:

- Do not start or restart `local.ios-portal.runner`.
- Do not run `xcodebuild test`, WebDriverAgent, or `pymobiledevice3 developer dvt xcuitest`.
- Do not reset the device's accessibility settings.
- For Expo Go recovery and screenshots, use the paired-device DVT path below. It does not start XCUITest and did not present the UI Automation prompt during the July 2026 recovery.

Incident lesson from 2026-07-14: an agent stopped the existing Expo/portal flow, attempted an XCTest-based restart, and incorrectly concluded that recovery required touching the phone. The paired-device DVT launch documented below recovered Expo Go without physical access. Treat it as the first-line recovery path for an unattended iPhone; do not repeat the XCTest restart first.

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

If the portal is not running and the device is unattended, stop here. Do not start it merely to reopen Expo Go; use the recovery procedure below.

## Recover Expo Go Without Physical Access

Use this when the portal or Expo Go was stopped and nobody can touch the iPhone. This is the known-good recovery path for `okm-app` on the Raspberry Pi.

### 1. Stop portal components that may relaunch XCUITest

```bash
launchctl remove local.ios-portal.runner 2>/dev/null || true
launchctl remove local.ios-portal.iproxy 2>/dev/null || true
lsof -tiTCP:16643 -sTCP:LISTEN | xargs -r kill
```

Confirm that no portal test process remains:

```bash
ps aux | rg 'xcodebuild test|DroidrunPortalServer|WebDriverAgent' | rg -v 'rg '
```

An empty result is expected.

### 2. Verify the paired device and the Pi services

```bash
UDID=52181a4873864c3323d52b4bc0c87d3068617f31

idevice_id -l
ideviceinfo -u "$UDID" -k ProductVersion

ssh alvin@raspberry-pi 'curl -fsS http://127.0.0.1:8081/status && echo'
ssh alvin@raspberry-pi 'curl -fsS http://127.0.0.1:54321/auth/v1/health && echo'
```

Expected results are the iPhone UDID, its iOS version, `packager-status:running`, and a GoTrue health response.

### 3. Find or prepare `pymobiledevice3`

Prefer an existing installation. The July 2026 recovery used this temporary virtual environment:

```bash
PMD3=/private/tmp/okm-pmd3-venv/bin/pymobiledevice3
```

If it no longer exists, recreate it without changing the project:

```bash
python3 -m venv /private/tmp/okm-pmd3-venv
/private/tmp/okm-pmd3-venv/bin/python -m pip install pymobiledevice3
PMD3=/private/tmp/okm-pmd3-venv/bin/pymobiledevice3
```

### 4. Launch Expo Go directly into the Pi bundle

The Pi's Tailscale address used by Expo is `100.76.99.124`. Keep the application identifier and its arguments together as one quoted positional argument:

```bash
"$PMD3" developer dvt launch \
  --udid "$UDID" \
  'host.exp.Exponent --initialUrl exp://100.76.99.124:8081'
```

This is the critical recovery command. Do not substitute the portal's `/inputs/launch` endpoint or an XCUITest launch when the device is unattended.

Wait for Metro to finish bundling, then confirm that Expo Go remains alive:

```bash
sleep 15
"$PMD3" developer dvt process-id-for-bundle-id \
  --udid "$UDID" \
  host.exp.Exponent
```

A numeric PID means Expo Go is running.

### 5. Clear a leftover Accessibility Inspector highlight

A translucent green rectangle is not an app defect. It is the Accessibility Audit inspector's `show visuals` overlay, which can remain on the iPhone after an interrupted inspection session. Turn off only the inspector overlay and monitoring session; do not call `reset_settings()`.

```bash
"$(dirname "$PMD3")/python" - <<'PY'
import asyncio

from pymobiledevice3.lockdown import create_using_usbmux
from pymobiledevice3.services.accessibilityaudit import AccessibilityAudit

UDID = "52181a4873864c3323d52b4bc0c87d3068617f31"


async def main():
    lockdown = await create_using_usbmux(serial=UDID)
    try:
        async with AccessibilityAudit(lockdown) as audit:
            await audit.set_show_visuals(False)
            await audit.set_app_monitoring_enabled(False)
            await audit.set_monitored_event_type(None)
    finally:
        await lockdown.close()


asyncio.run(main())
PY
```

### 6. Capture and verify the recovered screen

```bash
mkdir -p /tmp/okm-iphone7-recovery
idevicescreenshot \
  -u "$UDID" \
  /tmp/okm-iphone7-recovery/home.png
file /tmp/okm-iphone7-recovery/home.png
```

Open the PNG and verify all of the following before reporting recovery:

- There is no `Enable UI Automation` or Touch ID prompt.
- Expo Go shows the Okami app rather than its project list.
- The signed-in Home screen finishes loading.
- No green inspector rectangle covers the UI.

If the raw screenshot contains stale or missing compositor layers, use QuickTime Player as a read-only visual check: choose **File > New Movie Recording**, select **Alvin's iPhone 7** as the capture source, do not start recording, and close the preview after verification.

### Optional: scroll for screenshots without pressing app controls

Accessibility Audit focus traversal can scroll a React Native `ScrollView` to off-screen elements without activating buttons. Keep inspector visuals off, stop on the desired caption, and always disable monitoring afterward. Never call `perform_press()` or `reset_settings()` during unattended recovery.

This technique was used to capture the `Seven-round pulse`, `Resume`, and `Quick start` sections after Expo Go was recovered. It changes only the current scroll position; relaunch the same Expo URL afterward to leave Home at the top.

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
