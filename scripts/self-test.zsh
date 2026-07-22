#!/bin/zsh

set -euo pipefail

readonly BASE_URL="${PORTAL_BASE_URL:-http://127.0.0.1:16643}"
readonly OUTPUT_DIR="${TMPDIR:-/tmp}/ios-portal-self-test-$(/bin/date -u '+%Y%m%dT%H%M%SZ')"
readonly STATE_PATH="$OUTPUT_DIR/state.json"
readonly SCREENSHOT_PATH="$OUTPUT_DIR/screenshot.png"

mkdir -p "$OUTPUT_DIR"

request_json() {
    local method="$1"
    local path="$2"
    local body="${3:-}"

    if [[ -n "$body" ]]; then
        /usr/bin/curl -fsS --connect-timeout 3 --max-time 60 \
            -X "$method" -H 'Content-Type: application/json' -d "$body" \
            "$BASE_URL$path"
    else
        /usr/bin/curl -fsS --connect-timeout 3 --max-time 60 \
            -X "$method" "$BASE_URL$path"
    fi
}

capture_state() {
    request_json GET /state > "$STATE_PATH"
}

rect_for_identifier() {
    local identifier="$1"

    /usr/bin/ruby -rjson -e '
      tree = JSON.parse(File.read(ARGV[0])).fetch("a11y_tree")
      identifier = ARGV[1]
      line = tree.lines.find { |candidate| candidate.include?("identifier: \x27#{identifier}\x27") }
      abort("Accessibility identifier not found: #{identifier}") unless line
      match = line.match(/\{\{(-?[0-9.]+),\s*(-?[0-9.]+)\},\s*\{([0-9.]+),\s*([0-9.]+)\}\}/)
      abort("Element frame not found for: #{identifier}") unless match
      puts "{{#{match[1]},#{match[2]}},{#{match[3]},#{match[4]}}}"
    ' "$STATE_PATH" "$identifier"
}

print "Checking the supervised XCTest session..."
request_json GET /health | /usr/bin/jq -e '
  (.status == "ready" or .status == "busy") and
  (.sessionId | length > 0)
' > "$OUTPUT_DIR/health.json"

print "Activating the deterministic portal fixture..."
request_json POST /inputs/launch \
    '{"bundleIdentifier":"com.alvin.mobilerun-ios-portal"}' \
    > "$OUTPUT_DIR/launch.json"

# Resume state is intentionally preserved by activate(). Entering and leaving
# the fixture details screen dismisses any keyboard left by a previous client;
# two downward swipes then normalize the scroll position without terminating
# the app or risking the older-device XCTest termination failure.
capture_state
readonly NORMALIZE_DETAILS_RECT="$(rect_for_identifier fixture.open-details)"
request_json POST /gestures/tap \
    "{\"rect\":\"$NORMALIZE_DETAILS_RECT\",\"count\":1,\"longPress\":false}" \
    > "$OUTPUT_DIR/normalize-details-tap.json"
/bin/sleep 1
capture_state
/usr/bin/jq -e '.a11y_tree | contains("fixture.details-title")' "$STATE_PATH" >/dev/null
request_json POST /gestures/back > "$OUTPUT_DIR/normalize-back.json"
/bin/sleep 1
request_json POST /gestures/swipe \
    '{"x1":187,"y1":180,"x2":187,"y2":600,"durationMs":450}' \
    > "$OUTPUT_DIR/normalize-swipe-1.json"
request_json POST /gestures/swipe \
    '{"x1":187,"y1":180,"x2":187,"y2":600,"durationMs":450}' \
    > "$OUTPUT_DIR/normalize-swipe-2.json"
capture_state
/usr/bin/jq -e '
  (.a11y_tree | contains("fixture.title")) and
  (.a11y_tree | contains("Welcome to Droidrun!")) and
  (.device_context.screen_bounds.width == 375) and
  (.device_context.screen_bounds.height == 667)
' "$STATE_PATH" >/dev/null

print "Capturing the physical screen..."
/usr/bin/curl -fsS --connect-timeout 3 --max-time 60 \
    "$BASE_URL/vision/screenshot" -o "$SCREENSHOT_PATH"
readonly SCREENSHOT_WIDTH="$(/usr/bin/sips -g pixelWidth "$SCREENSHOT_PATH" | /usr/bin/awk '/pixelWidth/ {print $2}')"
readonly SCREENSHOT_HEIGHT="$(/usr/bin/sips -g pixelHeight "$SCREENSHOT_PATH" | /usr/bin/awk '/pixelHeight/ {print $2}')"
[[ "$SCREENSHOT_WIDTH" == 750 && "$SCREENSHOT_HEIGHT" == 1334 ]]

print "Testing coordinate tap against a live accessibility frame..."
readonly TAP_COUNT_BEFORE="$(/usr/bin/jq -r '.a11y_tree' "$STATE_PATH" | /usr/bin/sed -nE "s/.*label: 'Tap count: ([0-9]+)'.*/\1/p" | /usr/bin/head -n 1)"
readonly INCREMENT_RECT="$(rect_for_identifier fixture.increment)"
request_json POST /gestures/tap \
    "{\"rect\":\"$INCREMENT_RECT\",\"count\":1,\"longPress\":false}" \
    > "$OUTPUT_DIR/tap.json"
capture_state
readonly TAP_COUNT_AFTER="$(/usr/bin/jq -r '.a11y_tree' "$STATE_PATH" | /usr/bin/sed -nE "s/.*label: 'Tap count: ([0-9]+)'.*/\1/p" | /usr/bin/head -n 1)"
(( TAP_COUNT_AFTER == TAP_COUNT_BEFORE + 1 ))

print "Testing focused text input..."
readonly INPUT_RECT="$(rect_for_identifier fixture.input)"
request_json POST /inputs/type \
    "{\"rect\":\"$INPUT_RECT\",\"text\":\"physical-iphone7\",\"clear\":true}" \
    > "$OUTPUT_DIR/type.json"
capture_state
/usr/bin/jq -e '
  (.a11y_tree | contains("identifier: '\''fixture.input'\''")) and
  (.a11y_tree | contains("value: physical-iphone7")) and
  (.a11y_tree | contains("Input value: physical-iphone7"))
' "$STATE_PATH" >/dev/null

print "Testing navigation and back..."
readonly DETAILS_RECT="$(rect_for_identifier fixture.open-details)"
request_json POST /gestures/tap \
    "{\"rect\":\"$DETAILS_RECT\",\"count\":1,\"longPress\":false}" \
    > "$OUTPUT_DIR/details-tap.json"
/bin/sleep 1
capture_state
/usr/bin/jq -e '.a11y_tree | contains("fixture.details-title")' "$STATE_PATH" >/dev/null
request_json POST /gestures/back > "$OUTPUT_DIR/back.json"
/bin/sleep 1
capture_state
/usr/bin/jq -e '
  (.a11y_tree | contains("fixture.title")) and
  ((.a11y_tree | contains("fixture.details-title")) | not) and
  (.phone_state.keyboardVisible == false)
' "$STATE_PATH" >/dev/null

print "Testing a real scroll gesture..."
request_json POST /gestures/swipe \
    '{"x1":187,"y1":600,"x2":187,"y2":180,"durationMs":450}' \
    > "$OUTPUT_DIR/swipe-1.json"
request_json POST /gestures/swipe \
    '{"x1":187,"y1":600,"x2":187,"y2":180,"durationMs":450}' \
    > "$OUTPUT_DIR/swipe-2.json"
capture_state
/usr/bin/ruby -rjson -e '
  tree = JSON.parse(File.read(ARGV[0])).fetch("a11y_tree")
  line = tree.lines.find { |candidate| candidate.include?("identifier: \x27fixture.end\x27") }
  abort("Fixture end marker not found") unless line
  y = line.match(/\{\{[0-9.]+,\s*(-?[0-9.]+)\}/)[1].to_f
  abort("Fixture did not scroll into the physical viewport") unless y.between?(0, 667)
' "$STATE_PATH"

print "Testing fail-closed request serialization..."
typeset -a status_paths
for index in 1 2 3 4 5; do
    status_paths+=("$OUTPUT_DIR/concurrent-$index.status")
    (
        /usr/bin/curl -sS --max-time 60 \
            -o "$OUTPUT_DIR/concurrent-$index.json" \
            -w '%{http_code}' "$BASE_URL/state" \
            > "$OUTPUT_DIR/concurrent-$index.status"
    ) &
done
wait
readonly OK_COUNT="$(/usr/bin/grep -l '^200$' "${status_paths[@]}" | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
readonly BUSY_COUNT="$(/usr/bin/grep -l '^409$' "${status_paths[@]}" | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
[[ "$OK_COUNT" == 1 && "$BUSY_COUNT" == 4 ]]
for index in 1 2 3 4 5; do
    if [[ "$(<"$OUTPUT_DIR/concurrent-$index.status")" == 409 ]]; then
        /usr/bin/jq -e '.code == "portal_busy" and .retryable == true' \
            "$OUTPUT_DIR/concurrent-$index.json" >/dev/null
    fi
done

request_json GET /health | /usr/bin/jq -e '
  .status == "ready" and
  .busy == false and
  .lastError == null and
  (.lastSuccessfulAutomationAt | length > 0)
' > "$OUTPUT_DIR/final-health.json"

print "Physical iPhone 7 portal self-test passed. Evidence: $OUTPUT_DIR"
