#!/bin/zsh

set -u
setopt PIPE_FAIL

readonly REPO_DIR="/Users/alvin/Documents/Personal/Dev/mobile/ios-portal"
readonly DEVELOPER_DIR="/Applications/Xcode_26.2.app/Contents/Developer"
readonly XCODEBUILD="$DEVELOPER_DIR/usr/bin/xcodebuild"
readonly DEVICE_UDID="52181a4873864c3323d52b4bc0c87d3068617f31"
readonly DEVICE_PORT=6643
readonly HOST_PORT=16643
readonly HEALTH_URL="http://127.0.0.1:${HOST_PORT}/health"
readonly DERIVED_DATA_DIR="$HOME/Library/Developer/ios-portal/DerivedData"
readonly STATE_DIR="$HOME/Library/Application Support/ios-portal"
readonly STATUS_PATH="$STATE_DIR/status.json"
readonly LOCK_DIR="$STATE_DIR/supervisor.lock"
readonly LOG_DIR="$HOME/Library/Logs/ios-portal"
readonly RESULT_DIR="$LOG_DIR/results"
readonly RUNNER_LOG="$LOG_DIR/xcodebuild.log"
readonly IPROXY_LOG="$LOG_DIR/iproxy.log"
readonly SUPERVISOR_LOG="$LOG_DIR/supervisor.log"
readonly HEALTH_SAMPLE_LOG="$LOG_DIR/health-samples.jsonl"
readonly IPROXY="/opt/homebrew/bin/iproxy"
readonly IDEVICE_ID="/opt/homebrew/bin/idevice_id"
readonly JQ="/usr/bin/jq"
readonly CURL="/usr/bin/curl"
readonly CAFFEINATE="/usr/bin/caffeinate"

typeset -i runner_pid=0
typeset -i iproxy_pid=0
typeset -i owns_lock=0
typeset -i restart_count=0
typeset -i health_failures=0
typeset -i backoff_seconds=5
typeset -i last_profile_check_epoch=0
typeset profile_expires_at="unknown"
typeset last_health_at=""
typeset healthy_since=""
typeset last_error=""

mkdir -p "$STATE_DIR" "$LOG_DIR" "$RESULT_DIR" "$DERIVED_DATA_DIR"

timestamp() {
    /bin/date -u '+%Y-%m-%dT%H:%M:%SZ'
}

log() {
    print -r -- "$(timestamp) $*" | /usr/bin/tee -a "$SUPERVISOR_LOG"
}

write_status() {
    local phase="$1"
    local reason="$2"
    local temporary_path="${STATUS_PATH}.tmp.$$"

    "$JQ" -n \
        --arg phase "$phase" \
        --arg reason "$reason" \
        --arg updatedAt "$(timestamp)" \
        --arg deviceUdid "$DEVICE_UDID" \
        --arg xcode "$DEVELOPER_DIR" \
        --arg healthUrl "$HEALTH_URL" \
        --arg profileExpiresAt "$profile_expires_at" \
        --arg healthySince "$healthy_since" \
        --arg lastHealthAt "$last_health_at" \
        --arg lastError "$last_error" \
        --arg healthSampleLog "$HEALTH_SAMPLE_LOG" \
        --argjson devicePort "$DEVICE_PORT" \
        --argjson hostPort "$HOST_PORT" \
        --argjson runnerPid "$runner_pid" \
        --argjson iproxyPid "$iproxy_pid" \
        --argjson restartCount "$restart_count" \
        '{
            phase: $phase,
            reason: $reason,
            updatedAt: $updatedAt,
            deviceUdid: $deviceUdid,
            xcodeDeveloperDir: $xcode,
            healthUrl: $healthUrl,
            devicePort: $devicePort,
            hostPort: $hostPort,
            runnerPid: $runnerPid,
            iproxyPid: $iproxyPid,
            restartCount: $restartCount,
            healthSampleLog: $healthSampleLog,
            profileExpiresAt: $profileExpiresAt,
            healthySince: (if $healthySince == "" then null else $healthySince end),
            lastHealthAt: (if $lastHealthAt == "" then null else $lastHealthAt end),
            lastError: (if $lastError == "" then null else $lastError end)
        }' > "$temporary_path" && /bin/mv "$temporary_path" "$STATUS_PATH"
}

stop_pid() {
    local pid="$1"
    local name="$2"

    if (( pid <= 1 )) || ! /bin/kill -0 "$pid" 2>/dev/null; then
        return
    fi

    log "Stopping owned $name process $pid"
    /bin/kill -TERM "$pid" 2>/dev/null || true
    for _ in {1..20}; do
        /bin/kill -0 "$pid" 2>/dev/null || return
        /bin/sleep 0.25
    done
    /bin/kill -KILL "$pid" 2>/dev/null || true
}

stop_children() {
    stop_pid "$iproxy_pid" "iproxy"
    stop_pid "$runner_pid" "XCTest runner"
    iproxy_pid=0
    runner_pid=0
}

release_lock() {
    stop_children
    (( owns_lock == 1 )) || return
    /bin/unlink "$LOCK_DIR/pid" 2>/dev/null || true
    /bin/rmdir "$LOCK_DIR" 2>/dev/null || true
    owns_lock=0
}

trap release_lock EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

acquire_lock() {
    if /bin/mkdir "$LOCK_DIR" 2>/dev/null; then
        owns_lock=1
        return 0
    fi

    local existing_pid=""
    if [[ -f "$LOCK_DIR/pid" ]]; then
        existing_pid="$(<"$LOCK_DIR/pid")"
    fi

    if [[ "$existing_pid" == <-> ]] && /bin/kill -0 "$existing_pid" 2>/dev/null; then
        last_error="Supervisor process $existing_pid already owns the portal."
        return 1
    fi

    /bin/unlink "$LOCK_DIR/pid" 2>/dev/null || true
    /bin/rmdir "$LOCK_DIR" 2>/dev/null || true
    /bin/mkdir "$LOCK_DIR" || return 1
    owns_lock=1
}

require_dependencies() {
    local dependency
    for dependency in "$XCODEBUILD" "$IPROXY" "$IDEVICE_ID" "$JQ" "$CURL" "$CAFFEINATE"; do
        if [[ ! -x "$dependency" ]]; then
            last_error="Required executable is missing: $dependency"
            write_status "blocked" "$last_error"
            log "$last_error"
            return 1
        fi
    done

    if [[ ! -d "$REPO_DIR/droidrun-ios-portal.xcodeproj" ]]; then
        last_error="Portal project is missing at $REPO_DIR"
        write_status "blocked" "$last_error"
        log "$last_error"
        return 1
    fi
}

is_device_connected() {
    local device_list
    local -a connected_devices

    if ! device_list="$("$IDEVICE_ID" -l 2>&1)"; then
        log "USB discovery command failed: ${device_list:-no output}"
        return 1
    fi
    connected_devices=("${(@f)device_list}")
    if (( ${connected_devices[(Ie)$DEVICE_UDID]} == 0 )); then
        log "Required iPhone UDID was not observed; connected devices: ${device_list:-none}"
        return 1
    fi
    return 0
}

wait_for_stable_device() {
    local successful_samples=0

    while (( successful_samples < 3 )); do
        if ! is_device_connected; then
            return 1
        fi
        (( successful_samples += 1 ))
        (( successful_samples < 3 )) && /bin/sleep 2
    done
    return 0
}

check_profiles() {
    local -a required_identifiers=(
        "LR636MVRF3.com.alvin.mobilerun-ios-portal"
        "LR636MVRF3.com.alvin.mobilerun-ios-portalUITests"
        "LR636MVRF3.com.alvin.mobilerun-ios-portalUITests.xctrunner"
    )
    local -A newest_epoch
    local -A newest_iso
    local profile decoded identifier expiration expiration_epoch required
    local minimum_epoch=0
    local now_epoch="$(/bin/date -u +%s)"

    setopt LOCAL_OPTIONS NULL_GLOB
    for profile in "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"/*.mobileprovision; do
        decoded="$(/usr/bin/security cms -D -i "$profile" 2>/dev/null)" || continue
        identifier="$(print -r -- "$decoded" | /usr/bin/plutil -extract Entitlements.application-identifier raw -o - - 2>/dev/null)" || continue

        if (( ${required_identifiers[(Ie)$identifier]} == 0 )); then
            continue
        fi

        expiration="$(print -r -- "$decoded" | /usr/bin/plutil -extract ExpirationDate raw -o - - 2>/dev/null)" || continue
        expiration_epoch="$(/bin/date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$expiration" +%s 2>/dev/null)" || continue

        if [[ -z "${newest_epoch[$identifier]:-}" ]] || (( expiration_epoch > newest_epoch[$identifier] )); then
            newest_epoch[$identifier]="$expiration_epoch"
            newest_iso[$identifier]="$expiration"
        fi
    done

    for required in "${required_identifiers[@]}"; do
        if [[ -z "${newest_epoch[$required]:-}" ]]; then
            last_error="Required provisioning profile is missing: $required"
            profile_expires_at="unknown"
            return 1
        fi

        if (( minimum_epoch == 0 || newest_epoch[$required] < minimum_epoch )); then
            minimum_epoch="${newest_epoch[$required]}"
            profile_expires_at="${newest_iso[$required]}"
        fi
    done

    if (( minimum_epoch <= now_epoch )); then
        last_error="Portal provisioning expired at $profile_expires_at; rebuild with the iPhone physically available."
        return 1
    fi

    if (( minimum_epoch - now_epoch <= 86400 )); then
        log "Warning: portal provisioning expires within 24 hours at $profile_expires_at"
    fi

    last_profile_check_epoch="$now_epoch"
    return 0
}

health_check() {
    local response_path="$STATE_DIR/health.json"

    if "$CURL" -fsS --connect-timeout 3 --max-time 5 "$HEALTH_URL" -o "$response_path" &&
        "$JQ" -e '(.status == "ready" or .status == "busy") and (.sessionId | length > 0)' "$response_path" >/dev/null; then
        "$JQ" -c \
            --arg observedAt "$(timestamp)" \
            --argjson supervisorPid "$$" \
            --argjson restartCount "$restart_count" \
            '. + {
                observedAt: $observedAt,
                supervisorPid: $supervisorPid,
                restartCount: $restartCount,
                reachable: true
            }' "$response_path" >> "$HEALTH_SAMPLE_LOG"
        return 0
    fi

    "$JQ" -nc \
        --arg observedAt "$(timestamp)" \
        --argjson supervisorPid "$$" \
        --argjson restartCount "$restart_count" \
        '{
            observedAt: $observedAt,
            supervisorPid: $supervisorPid,
            restartCount: $restartCount,
            reachable: false
        }' >> "$HEALTH_SAMPLE_LOG"
    return 1
}

start_children() {
    local result_bundle="$RESULT_DIR/portal-$(/bin/date -u '+%Y%m%dT%H%M%SZ')-supervisor-$$-restart-${restart_count}.xcresult"

    log "Starting physical-device XCTest runner with Xcode 26.2"
    (
        cd "$REPO_DIR" || exit 1
        exec "$CAFFEINATE" -is /usr/bin/env \
            DEVELOPER_DIR="$DEVELOPER_DIR" \
            "$XCODEBUILD" test-without-building \
            -skipMacroValidation \
            -project droidrun-ios-portal.xcodeproj \
            -scheme droidrun-ios-portal \
            -derivedDataPath "$DERIVED_DATA_DIR" \
            -destination "platform=iOS,id=$DEVICE_UDID" \
            -parallel-testing-enabled NO \
            -resultBundlePath "$result_bundle" \
            "-only-testing:Droidrun Server/DroidrunPortalServer/testLoop"
    ) >> "$RUNNER_LOG" 2>&1 &
    runner_pid=$!

    log "Starting USB port forward $HOST_PORT -> $DEVICE_PORT"
    "$IPROXY" "$HOST_PORT" "$DEVICE_PORT" -u "$DEVICE_UDID" >> "$IPROXY_LOG" 2>&1 &
    iproxy_pid=$!
}

wait_until_ready() {
    local attempts=0

    while (( attempts < 60 )); do
        if ! /bin/kill -0 "$runner_pid" 2>/dev/null; then
            last_error="The XCTest runner exited before the health endpoint became ready."
            return 1
        fi
        if ! /bin/kill -0 "$iproxy_pid" 2>/dev/null; then
            last_error="iproxy exited before the health endpoint became ready."
            return 1
        fi
        if health_check; then
            last_health_at="$(timestamp)"
            healthy_since="$last_health_at"
            last_error=""
            return 0
        fi
        (( attempts += 1 ))
        /bin/sleep 3
    done

    last_error="The physical-device portal did not become healthy within 180 seconds."
    return 1
}

restart_after_failure() {
    local reason="$1"

    last_error="$reason"
    (( restart_count += 1 ))
    write_status "restarting" "$reason"
    log "$reason Restarting in $backoff_seconds seconds."
    stop_children
    /bin/sleep "$backoff_seconds"
    (( backoff_seconds = backoff_seconds < 120 ? backoff_seconds * 2 : 120 ))
}

main() {
    acquire_lock || return 75
    print -r -- "$$" > "$LOCK_DIR/pid"
    require_dependencies || return 69
    write_status "starting" "Supervisor is validating the physical device and signing state."

    while true; do
        if ! check_profiles; then
            stop_children
            healthy_since=""
            write_status "blocked_signing" "$last_error"
            log "$last_error"
            /bin/sleep 300
            continue
        fi

        if ! wait_for_stable_device; then
            last_error="Physical iPhone 7 is not stably connected at the required UDID."
            stop_children
            healthy_since=""
            write_status "disconnected" "$last_error"
            /bin/sleep 15
            continue
        fi

        write_status "starting" "Starting the signed XCTest runner and USB forwarder."
        start_children
        if ! wait_until_ready; then
            restart_after_failure "$last_error"
            continue
        fi

        health_failures=0
        backoff_seconds=5
        write_status "healthy" "Physical-device XCTest portal is ready."
        log "Portal is healthy at $HEALTH_URL"

        while true; do
            /bin/sleep 15

            if ! /bin/kill -0 "$runner_pid" 2>/dev/null; then
                restart_after_failure "The XCTest runner exited unexpectedly."
                break
            fi
            if ! /bin/kill -0 "$iproxy_pid" 2>/dev/null; then
                restart_after_failure "iproxy exited unexpectedly."
                break
            fi
            if ! is_device_connected; then
                restart_after_failure "The physical iPhone 7 disconnected from USB."
                break
            fi

            local now_epoch="$(/bin/date -u +%s)"
            if (( now_epoch - last_profile_check_epoch >= 300 )) && ! check_profiles; then
                restart_after_failure "$last_error"
                break
            fi

            if health_check; then
                health_failures=0
                last_health_at="$(timestamp)"
                last_error=""
                write_status "healthy" "Physical-device XCTest portal is ready."
            else
                (( health_failures += 1 ))
                last_error="Health check failed $health_failures of 3 times."
                write_status "degraded" "$last_error"
                if (( health_failures >= 3 )); then
                    restart_after_failure "The portal health endpoint failed three consecutive checks."
                    break
                fi
            fi
        done
    done
}

main "$@"
