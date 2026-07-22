# Physical iPhone 7 Portal Handoff

This is the authoritative runbook for automated UI testing on Alvin's physically connected iPhone 7. The supported path is deliberately narrow: Xcode 26.2 runs this repository's signed XCTest bundle on the named USB device, `iproxy` forwards one fixed port, and one launchd supervisor owns both processes.

## Fixed configuration

| Item | Required value |
| --- | --- |
| Repository | `/Users/alvin/Documents/Personal/Dev/mobile/ios-portal` |
| Xcode | `/Applications/Xcode_26.2.app/Contents/Developer` |
| Device | `Alvin's iPhone 7`, iOS 15.8.8 |
| UDID | `52181a4873864c3323d52b4bc0c87d3068617f31` |
| Portal app | `com.alvin.mobilerun-ios-portal` |
| Device port | `6643` |
| Mac port | `16643` |
| Base URL | `http://127.0.0.1:16643` |
| LaunchAgent | `com.alvin.ios-portal.supervisor` |
| Status | `~/Library/Application Support/ios-portal/status.json` |
| Logs | `~/Library/Logs/ios-portal/` |
| Soak samples | `~/Library/Logs/ios-portal/health-samples.jsonl` |

Do not substitute the default Xcode, a simulator, network pairing, WebDriverAgent, Shortcuts, DVT, `pymobiledevice3`, raw screenshot tools, or another launch mechanism. They are not portal recovery paths and cannot count as successful UI Automation. The API also does not fabricate empty accessibility trees, guessed screen sizes, or success responses when XCTest cannot reach the target app.

Mirage Host may remain installed and running. Xcode and QuickTime do not need to remain open after installation.

## One-time installation or rebuild

Run this while Alvin is physically present, the iPhone is unlocked and trusted, and **Settings > Developer > Enable UI Automation** is on:

```bash
cd /Users/alvin/Documents/Personal/Dev/mobile/ios-portal
./scripts/install-launch-agent.zsh
```

The installer performs a signed `build-for-testing` with the pinned Xcode and device, installs the LaunchAgent, and starts the supervisor. Approve any trust or UI Automation prompt on the iPhone. The unattended supervisor subsequently uses only `test-without-building`; it does not silently renew or replace signing assets.

Re-run the installer after portal code changes, after renewing Personal Team profiles, or when changing the qualified Xcode version. A successful generic build is not enough—the installer must successfully build for this UDID.

## Normal health check

The status file explains whether the portal is healthy, disconnected, restarting, or blocked by signing:

```bash
jq . "$HOME/Library/Application Support/ios-portal/status.json"
curl -fsS http://127.0.0.1:16643/health | jq .
launchctl print "gui/$(id -u)/com.alvin.ios-portal.supervisor"
```

Healthy service state requires all of the following:

- `status.json` has `phase: "healthy"`.
- `/health` returns `status` as `ready` or `busy`, a non-empty `sessionId`, and the pinned server session metadata.
- The recorded `runnerPid` and `iproxyPid` belong to the supervisor.
- The device is still listed by `idevice_id -l` with the exact UDID.

The supervisor takes `caffeinate -is` assertions while the XCTest runner is alive, checks USB and HTTP health every 15 seconds, and restarts its own children after three consecutive health failures. Restart delay backs off from 5 to 120 seconds. It never kills an unrelated Xcode, Mirage, or USB process.

Each health attempt is appended as JSON Lines evidence. Summarize all samples, or
only samples at and after an ISO-8601 soak start time, with:

```bash
cd /Users/alvin/Documents/Personal/Dev/mobile/ios-portal
./scripts/soak-report.zsh
./scripts/soak-report.zsh 2026-07-19T03:00:00Z
```

## Required UI Automation self-test

Service health proves that the runner is reachable. Actual UI Automation is accepted only after a real app activation, accessibility query, and screenshot all succeed:

```bash
cd /Users/alvin/Documents/Personal/Dev/mobile/ios-portal
./scripts/self-test.zsh
```

The versioned self-test also exercises tap, focused typing, navigation, back,
scrolling, and concurrent-request rejection. Its evidence directory is printed at
the end. For a short manual confirmation, run:

```bash
BASE=http://127.0.0.1:16643
STATE=/tmp/ios-portal-iphone7-state.json
SHOT=/tmp/ios-portal-iphone7-screenshot.png

curl -fsS "$BASE/health" | jq .
curl -fsS \
  -H 'Content-Type: application/json' \
  -d '{"bundleIdentifier":"com.alvin.mobilerun-ios-portal"}' \
  "$BASE/inputs/launch" | jq .
curl -fsS "$BASE/state" -o "$STATE"
curl -fsS "$BASE/vision/screenshot" -o "$SHOT"

jq -e '
  (.a11y_tree | contains("fixture.title")) and
  (.a11y_tree | contains("Welcome to Droidrun!")) and
  (.device_context.screen_bounds.width == 375) and
  (.device_context.screen_bounds.height == 667)
' "$STATE"
sips -g pixelWidth -g pixelHeight "$SHOT"
file "$SHOT"
```

On this iPhone the screenshot must be a valid `750 x 1334` PNG. A USB connection, a visible app, `/health`, or `/device/date` by itself is insufficient proof. HTTP 409 means another operation is active; wait for it. HTTP 503 means XCTest could not perform the operation; do not reinterpret it as success.

For Expo Go flow tests, use a fresh launch before opening the project deep link
when an existing JavaScript session is stale or does not accept input:

```bash
curl -fsS \
  -H 'Content-Type: application/json' \
  -d '{"bundleIdentifier":"host.exp.Exponent","fresh":true}' \
  "$BASE/inputs/launch" | jq .
```

The default remains resumptive activation. Use `fresh: true` only at an explicit
test boundary; it intentionally asks XCTest to replace the existing app process.

## Supervisor behavior and recovery

The service has one owner and one recovery loop:

1. Verify the three required signing profiles exist and have not expired.
2. Observe the exact physical UDID three consecutive times.
3. Start the prebuilt XCTest bundle and fixed USB port forwarder.
4. Wait up to 180 seconds for `/health`.
5. Monitor the runner, forwarder, USB device, profiles, and health endpoint.
6. Restart both owned child processes when the session becomes unhealthy.

Read status and logs before intervening:

```bash
jq . "$HOME/Library/Application Support/ios-portal/status.json"
tail -n 100 "$HOME/Library/Logs/ios-portal/supervisor.log"
tail -n 150 "$HOME/Library/Logs/ios-portal/xcodebuild.log"
tail -n 100 "$HOME/Library/Logs/ios-portal/iproxy.log"
```

The expected failure states are explicit:

- `disconnected`: restore the qualified physical cable and port; the supervisor waits for three stable observations.
- `blocked_signing`: Alvin must be present to renew and rebuild. No unsigned or alternate runner is attempted.
- `restarting`: inspect `lastError` and the matching logs. Backoff is in progress.
- `degraded`: one or two health checks failed; the third consecutive failure triggers a restart.
- `blocked`: a dependency, repository, or single-owner invariant is broken.

If UI Automation is disabled or iOS presents a confirmation prompt, the portal remains unavailable until somebody can touch the iPhone. There is intentionally no unattended fallback.

## Signing lifecycle

This project uses Alvin's free Personal Team `LR636MVRF3`, so the portal app and XCTest runner profiles expire after roughly seven days. The supervisor requires all three application identifiers and hard-stops at the earliest expiry:

- `LR636MVRF3.com.alvin.mobilerun-ios-portal`
- `LR636MVRF3.com.alvin.mobilerun-ios-portalUITests`
- `LR636MVRF3.com.alvin.mobilerun-ios-portalUITests.xctrunner`

Inspect their current expiry without changing anything:

```bash
for profile in "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"/*.mobileprovision; do
  decoded=$(security cms -D -i "$profile" 2>/dev/null) || continue
  identifier=$(printf '%s' "$decoded" | plutil \
    -extract Entitlements.application-identifier raw -o - - 2>/dev/null) || continue
  if [[ "$identifier" == *mobilerun-ios-portal* ]]; then
    expiration=$(printf '%s' "$decoded" | plutil \
      -extract ExpirationDate raw -o - -)
    printf '%s\t%s\n' "$identifier" "$expiration"
  fi
done
```

To renew, Alvin must be present:

1. Open Xcode 26.2 **Settings > Accounts** and select the Personal Team.
2. Download profiles and ensure both targets use automatic signing with that team.
3. Run `./scripts/install-launch-agent.zsh` and approve any iPhone prompt.
4. Confirm the three new expiry dates.
5. Run the complete UI Automation self-test above.

The supervisor warns in its log during the final 24 hours. It does not claim that free signing can provide more than the profile lifetime.

## Start, restart, and stop

Start or force a supervised restart:

```bash
launchctl kickstart -k "gui/$(id -u)/com.alvin.ios-portal.supervisor"
```

Stop it without deleting logs, results, status, or builds:

```bash
cd /Users/alvin/Documents/Personal/Dev/mobile/ios-portal
./scripts/uninstall-launch-agent.zsh
```

Install again with the one-time installation command. Do not run a second foreground `xcodebuild test` or `iproxy` beside the supervisor; concurrent owners make results ambiguous and cause port conflicts.

## Cable, port, and Xcode qualification

When flakiness returns, qualify one variable at a time while Alvin is present:

1. Stop the LaunchAgent.
2. Connect the iPhone directly to the Mac—no hub or display passthrough.
3. Record the exact cable and Mac port.
4. Install and run the full UI Automation self-test.
5. Hold the same configuration for a transport soak and search the system log for `usbmuxd` disconnects.
6. Repeat with the alternate cable or port.
7. Keep only the configuration with zero unexpected disconnects and a continuously healthy portal.

The current pinned Xcode is 26.2. On 2026-07-19, Xcode 26.6 completed a signed physical-device `build-for-testing` but its matching `test-without-building` rejected `Droidrun Server` as unsupported logic testing on the iPhone 7. It is therefore unqualified and must not replace 26.2. Merely being the default `xcode-select` version or passing a build does not qualify a toolchain.

## Mac login limitation

FileVault is enabled and automatic login is unavailable. After a full Mac reboot, a person must unlock and log into the Mac before this per-user LaunchAgent can run. Once logged in, the supervisor starts automatically. This is an explicit availability boundary, not something the portal can bypass.
