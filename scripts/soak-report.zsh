#!/bin/zsh

set -euo pipefail

readonly SAMPLE_LOG="$HOME/Library/Logs/ios-portal/health-samples.jsonl"
readonly FROM_TIMESTAMP="${1:-1970-01-01T00:00:00Z}"

if [[ ! -s "$SAMPLE_LOG" ]]; then
    print -u2 "No supervisor health samples exist at $SAMPLE_LOG"
    exit 1
fi

/usr/bin/jq -s --arg from "$FROM_TIMESTAMP" '
  map(select(.observedAt >= $from)) as $samples |
  {
    from: $from,
    firstObservedAt: ($samples | map(.observedAt) | min // null),
    lastObservedAt: ($samples | map(.observedAt) | max // null),
    sampleCount: ($samples | length),
    reachableCount: ($samples | map(select(.reachable == true)) | length),
    unreachableCount: ($samples | map(select(.reachable != true)) | length),
    sessionIds: ($samples | map(.sessionId // empty) | unique),
    supervisorPids: ($samples | map(.supervisorPid) | unique),
    maximumRestartCount: ($samples | map(.restartCount) | max // 0),
    reportedAutomationErrors: ($samples | map(.lastError // empty) | unique)
  }
' "$SAMPLE_LOG"
