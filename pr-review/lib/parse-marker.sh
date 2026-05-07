#!/usr/bin/env bash
# parse-marker.sh — sourceable helper: parse the claude-pr-review-summary-v1
# structured marker from a PR review body.
#
# Usage:
#   source parse-marker.sh
#   outcome=$(parse_marker <body-file>)
#   # or via stdin:
#   outcome=$(echo "$BODY" | parse_marker)
#
# Output format (stdout, one line):
#   outcome|critical|high|medium|low
#
# Outcome values:
#   marker_missing  — sentinel not found in body (counts are all 0)
#   marker_invalid  — sentinel found but JSON malformed or schema check fails
#   clean           — schema valid AND critical==0 AND high==0
#   blocking        — schema valid AND (critical>0 OR high>0)
#
# For marker_missing and marker_invalid, counts are emitted as 0.
#
# Design notes:
#   - TOP-LEVEL scope sets NO flags so callers' shells are unaffected.
#   - The function uses `local -` to scope its own `set -uo pipefail`.
#   - Accepts body as a file path argument OR on stdin (if no arg given).
#   - Anchors on the exact sentinel line `<!-- claude-pr-review-summary-v1`
#     (no trailing space, no variations) per the plan locked decision #1.
#   - Extra top-level JSON keys outside schemaVersion/findings are rejected
#     (schema is closed per the plan and the persona's CLAUDE.md).

# shellcheck disable=SC2016

parse_marker() {
  local -

  set -uo pipefail

  local body_input
  if [ "${1:-}" != "" ]; then
    body_input=$(cat "$1")
  else
    body_input=$(cat)
  fi

  # --- Step 1: Locate the sentinel --------------------------------------------
  # The sentinel must appear at the start of an HTML comment opening line.
  # Extract everything from the sentinel line through the closing -->.
  local sentinel="<!-- claude-pr-review-summary-v1"

  if ! printf '%s\n' "$body_input" | grep -qF "$sentinel"; then
    printf 'marker_missing|0|0|0|0\n'
    return 0
  fi

  # --- Step 2: Extract the JSON slice between sentinel and --> ---------------
  # Strategy: use awk to capture lines from the sentinel through the first
  # closing --> that follows it.
  local raw_json
  raw_json=$(printf '%s\n' "$body_input" | awk '
    BEGIN { capturing=0; buf="" }
    /<!-- claude-pr-review-summary-v1/ {
      capturing=1
      # Skip the sentinel line itself — only capture JSON lines after it
      next
    }
    capturing==1 {
      if (/-->/) {
        # End of block — stop capturing (do not include the --> line)
        capturing=0
        exit
      }
      buf = buf $0 "\n"
    }
    END { printf "%s", buf }
  ')

  if [ -z "$raw_json" ]; then
    printf 'marker_invalid|0|0|0|0\n'
    return 0
  fi

  # --- Step 3: Validate JSON is parseable ------------------------------------
  if ! printf '%s\n' "$raw_json" | jq . >/dev/null 2>&1; then
    printf 'marker_invalid|0|0|0|0\n'
    return 0
  fi

  # --- Step 4: Schema check ---------------------------------------------------
  # Required: schemaVersion (integer), findings.{critical,high,medium,low} (integers >=0)
  # Forbidden: any extra top-level keys outside schemaVersion and findings.

  # Check schemaVersion is present and is a number
  local schema_version
  schema_version=$(printf '%s\n' "$raw_json" | jq -r '.schemaVersion // "MISSING"' 2>/dev/null)
  if [ "$schema_version" = "MISSING" ]; then
    printf 'marker_invalid|0|0|0|0\n'
    return 0
  fi
  if ! printf '%s\n' "$raw_json" | jq -e '.schemaVersion | type == "number"' >/dev/null 2>&1; then
    printf 'marker_invalid|0|0|0|0\n'
    return 0
  fi

  # Check findings object is present
  if ! printf '%s\n' "$raw_json" | jq -e '.findings | type == "object"' >/dev/null 2>&1; then
    printf 'marker_invalid|0|0|0|0\n'
    return 0
  fi

  # Check all four findings fields exist and are non-negative integers
  local field
  for field in critical high medium low; do
    local val
    val=$(printf '%s\n' "$raw_json" | jq -r ".findings.${field} // \"MISSING\"" 2>/dev/null)
    if [ "$val" = "MISSING" ]; then
      printf 'marker_invalid|0|0|0|0\n'
      return 0
    fi
    # Must be a number (not a string)
    if ! printf '%s\n' "$raw_json" | jq -e ".findings.${field} | type == \"number\"" >/dev/null 2>&1; then
      printf 'marker_invalid|0|0|0|0\n'
      return 0
    fi
    # Must be >= 0
    if ! printf '%s\n' "$raw_json" | jq -e ".findings.${field} >= 0" >/dev/null 2>&1; then
      printf 'marker_invalid|0|0|0|0\n'
      return 0
    fi
  done

  # Check no extra top-level keys outside schemaVersion and findings
  local extra_keys
  extra_keys=$(printf '%s\n' "$raw_json" | jq -r 'keys[] | select(. != "schemaVersion" and . != "findings")' 2>/dev/null)
  if [ -n "$extra_keys" ]; then
    printf 'marker_invalid|0|0|0|0\n'
    return 0
  fi

  # --- Step 5: Extract counts and derive verdict -----------------------------
  local critical high medium low
  critical=$(printf '%s\n' "$raw_json" | jq -r '.findings.critical')
  high=$(printf '%s\n' "$raw_json" | jq -r '.findings.high')
  medium=$(printf '%s\n' "$raw_json" | jq -r '.findings.medium')
  low=$(printf '%s\n' "$raw_json" | jq -r '.findings.low')

  # Verdict rule (locked decision #3): blocking if critical>0 OR high>0
  if [ "$critical" -gt 0 ] || [ "$high" -gt 0 ]; then
    printf 'blocking|%s|%s|%s|%s\n' "$critical" "$high" "$medium" "$low"
  else
    printf 'clean|%s|%s|%s|%s\n' "$critical" "$high" "$medium" "$low"
  fi

  return 0
}
