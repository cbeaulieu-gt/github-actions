#!/usr/bin/env bash
# run-marker-cases.sh — fixture-driven test runner for pr-review/lib/parse-marker.sh.
#
# Usage: bash run-marker-cases.sh
#
# Sources pr-review/lib/parse-marker.sh, iterates every .md fixture in
# pr-review/tests/marker-cases/, reads its sibling .expected sidecar, runs
# parse_marker against the fixture, and compares actual vs expected outcome.
# Exits 0 if all cases pass, 1 if any fail.
#
# Expected sidecar format (.expected file, one line):
#   marker_missing           — for marker_missing outcome (counts not checked)
#   marker_invalid           — for marker_invalid outcome (counts not checked)
#   clean|0|0|0|0            — full wire format for clean/blocking outcomes
#   blocking|1|1|1|1         — full wire format
#
# For marker_missing and marker_invalid, only the outcome token is compared;
# the count fields (which are 0 placeholders) are ignored. This matches the
# parse-marker.sh contract where counts are not meaningful in error states.
#
# Failures ACCUMULATE — every mismatched case is reported before exit 1.
# Set is `set -uo pipefail`, NOT `-e`, to allow accumulation.

set -uo pipefail

# Resolve paths via the script's location so this works from any cwd.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PR_REVIEW_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PARSE_SH="$PR_REVIEW_DIR/lib/parse-marker.sh"
FIXTURES_DIR="$SCRIPT_DIR/marker-cases"

# --- Defensive startup checks -------------------------------------------------

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR jq_not_found: jq is required (preinstalled on ubuntu-latest)" >&2
  exit 1
fi

if [ ! -f "$PARSE_SH" ]; then
  echo "ERROR parse_sh_missing: $PARSE_SH" >&2
  exit 1
fi

if [ ! -d "$FIXTURES_DIR" ]; then
  echo "ERROR fixtures_dir_missing: $FIXTURES_DIR" >&2
  exit 1
fi

# Minimum fixture count check.
fixture_count=$(find "$FIXTURES_DIR" -maxdepth 1 -name '*.md' | wc -l)
if [ "$fixture_count" -lt 5 ]; then
  echo "ERROR fixtures_too_few: found $fixture_count .md fixtures in $FIXTURES_DIR, want >= 5" >&2
  exit 1
fi

# --- Source parser ------------------------------------------------------------

# parse-marker.sh's TOP-LEVEL scope sets no flags (design invariant).
# The function `parse_marker` uses `local -` to scope its own flags.
# shellcheck disable=SC1090
source "$PARSE_SH"

if ! declare -F parse_marker >/dev/null; then
  echo "ERROR parse_marker_undefined: sourcing $PARSE_SH did not define parse_marker" >&2
  exit 1
fi

# --- Iterate fixtures ---------------------------------------------------------

errs=0
total=0

for fixture in "$FIXTURES_DIR"/*.md; do
  total=$((total + 1))
  name=$(basename "$fixture" .md)
  expected_file="${fixture%.md}.expected"

  if [ ! -f "$expected_file" ]; then
    errs=$((errs + 1))
    printf 'FAIL: %s\n  missing sidecar: %s\n' "$name" "$expected_file" >&2
    continue
  fi

  # Read expected outcome (trim trailing newline/whitespace)
  expected=$(tr -d '[:space:]' < "$expected_file")

  # Run parser against the fixture file
  actual=$(parse_marker "$fixture")
  rc=$?
  if [ "$rc" != "0" ]; then
    errs=$((errs + 1))
    printf 'FAIL: %s\n  parse_marker exited rc=%s (expected 0)\n' "$name" "$rc" >&2
    continue
  fi

  # For marker_missing and marker_invalid, compare only the outcome token
  # (the count fields are 0 placeholders and not meaningful in error states).
  actual_outcome=$(printf '%s' "$actual" | cut -d'|' -f1)
  expected_outcome=$(printf '%s' "$expected" | cut -d'|' -f1)

  if [ "$expected_outcome" = "marker_missing" ] || [ "$expected_outcome" = "marker_invalid" ]; then
    # Outcome-only comparison
    if [ "$actual_outcome" != "$expected_outcome" ]; then
      errs=$((errs + 1))
      printf 'FAIL: %s\n  expected outcome: [%s]\n  got:              [%s]\n  full output: [%s]\n' \
        "$name" "$expected_outcome" "$actual_outcome" "$actual" >&2
    fi
  else
    # Full wire-format comparison (outcome|critical|high|medium|low)
    if [ "$actual" != "$expected" ]; then
      errs=$((errs + 1))
      printf 'FAIL: %s\n  expected: [%s]\n  got:      [%s]\n' "$name" "$expected" "$actual" >&2
    fi
  fi
done

# --- Summary ------------------------------------------------------------------

passed=$((total - errs))
printf 'summary: %d/%d passed\n' "$passed" "$total"

if [ "$errs" -gt 0 ]; then
  exit 1
fi
exit 0
