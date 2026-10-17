#!/usr/bin/env bash
# Sends one notification to notify-services. Called by action.yml; every
# value arrives as an environment variable (never spliced into this script),
# so a commit message with quotes or $(...) in it is just text.
#
# Two ways to be called:
#   - NOTIFY_MESSAGE set: sent as it is, with NOTIFY_TITLE and NOTIFY_LEVEL
#     (the original behaviour, kept so existing workflows don't change).
#   - NOTIFY_MESSAGE empty: the title, body and level are built here from
#     NOTIFY_EVENT, NOTIFY_JOBS / NOTIFY_STATUS and the GitHub run, so every
#     repository reports in the same shape.
#
# NOTIFY_DRY_RUN=1 prints the request body instead of sending it.
set -euo pipefail

event_label() {
  case "$1" in
    deploy) echo "Deploy" ;;
    build) echo "Build" ;;
    test) echo "Test" ;;
    backup) echo "Sao lưu" ;;
    release) echo "Release" ;;
    rollback) echo "Quay về bản cũ" ;;
    *) echo "$1" ;;
  esac
}

# Overall result from the needs context: one failed job fails the run, then a
# cancelled one cancels it; skipped jobs don't count against it.
status_from_jobs() {
  jq -r '
    [.[].result] as $r
    | if ($r | index("failure")) then "failure"
      elif ($r | index("cancelled")) then "cancelled"
      else "success" end' <<<"$1"
}

# "test ✓ · build-and-push ✓ · deploy ✗", in the order the jobs were listed.
jobs_line() {
  jq -r '
    to_entries
    | map(.key + " " + ({"success":"✓","failure":"✗","cancelled":"⊘","skipped":"–"}[.value.result] // .value.result))
    | join(" · ")' <<<"$1"
}

build_message() {
  local jobs="${NOTIFY_JOBS:-}"
  [ "$jobs" = "null" ] && jobs=""
  if [ -n "$jobs" ] && [ "$jobs" != "{}" ]; then
    jq -e 'type == "object"' >/dev/null <<<"$jobs" ||
      { echo "jobs must be \${{ toJSON(needs) }}" >&2; exit 1; }
  fi

  local status="${NOTIFY_STATUS:-}"
  if [ -z "$status" ]; then
    if [ -z "$jobs" ] || [ "$jobs" = "{}" ]; then
      echo "set status (success, failure, cancelled) or jobs (\${{ toJSON(needs) }})" >&2
      exit 1
    fi
    status=$(status_from_jobs "$jobs")
  fi

  local result
  case "$status" in
    success) result="thành công"; level="info" ;;
    failure) result="thất bại"; level="error" ;;
    cancelled) result="bị hủy"; level="warning" ;;
    *) echo "status must be success, failure or cancelled, got '$status'" >&2; exit 1 ;;
  esac
  [ -n "${NOTIFY_LEVEL:-}" ] && level="$NOTIFY_LEVEL"

  title="$(event_label "${NOTIFY_EVENT:-deploy}") $result"
  [ -n "${NOTIFY_TARGET:-}" ] && title="$title · $NOTIFY_TARGET"

  local sha="${GITHUB_SHA:-}"
  local subject=""
  if [ -n "${GITHUB_EVENT_PATH:-}" ] && [ -f "$GITHUB_EVENT_PATH" ]; then
    # First line only, cut by characters (not bytes, which would split a
    # Vietnamese letter in two).
    subject=$(jq -r '(.head_commit.message // .pull_request.title // .workflow_run.head_commit.message // "")
      | split("\n")[0] | .[0:72]' "$GITHUB_EVENT_PATH")
    # A workflow_run event runs on the default branch; the commit that was
    # deployed is the one the triggering run was for.
    local run_sha
    run_sha=$(jq -r '.workflow_run.head_sha // ""' "$GITHUB_EVENT_PATH")
    [ -n "$run_sha" ] && sha="$run_sha"
  fi

  local lines=()
  lines+=("Repo: ${GITHUB_REPOSITORY:-}")
  if [ -n "$subject" ]; then
    lines+=("Commit: ${sha:0:12} $subject")
  else
    lines+=("Commit: ${sha:0:12}")
  fi
  lines+=("Người: ${GITHUB_ACTOR:-}")
  if [ -n "$jobs" ] && [ "$jobs" != "{}" ]; then
    lines+=("Các bước: $(jobs_line "$jobs")")
  fi
  if [ -n "${NOTIFY_DETAILS:-}" ]; then
    while IFS= read -r line; do
      [ -n "$line" ] && lines+=("$line")
    done <<<"$NOTIFY_DETAILS"
  fi
  lines+=("Run: ${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-}/actions/runs/${GITHUB_RUN_ID:-}")

  message=$(printf '%s\n' "${lines[@]}")
  message="${message%$'\n'}"
}

title="${NOTIFY_TITLE:-}"
level="${NOTIFY_LEVEL:-info}"
message="${NOTIFY_MESSAGE:-}"

# With no message, the level follows the result unless one was given.
if [ -z "$message" ]; then
  user_title="$title"
  build_message
  [ -n "$user_title" ] && title="$user_title"
fi

body=$(jq -n \
  --arg service "${NOTIFY_SERVICE:?service is required}" \
  --arg title "$title" \
  --arg message "$message" \
  --arg level "$level" \
  --arg to "${NOTIFY_TO:-}" \
  '{service: $service, title: $title, message: $message, level: $level}
   + (if $to == "" then {} else {to: ($to | split(",") | map(gsub("^\\s+|\\s+$";"")))} end)')

if [ -n "${NOTIFY_DRY_RUN:-}" ]; then
  echo "$body"
  exit 0
fi

curl -sf -X POST "${NOTIFY_API_URL:-https://notify-api.thomas-labs.com}/v1/notify" \
  -H "Authorization: Bearer ${NOTIFY_API_KEY:?api-key is required}" \
  -H "Content-Type: application/json" \
  -d "$body"
