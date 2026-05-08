# 2026-05-08 — Marker Synthesis via Post-Processing (Phase 1 of runtime overlay recovery)

**Status: DRAFT — pending second inquisitor pass**

| Field | Value |
|---|---|
| Created | 2026-05-08 |
| Phase | 1 of 2 |
| Issues | [#242](https://github.com/glitchwerks/github-actions/issues/242) (closes when W3 lands), [#245](https://github.com/glitchwerks/github-actions/issues/245) (remains open — W1+W2 verification tracker) |
| Scope | W3 only — marker post-processing |

---

## Why W1 and W2 are deferred

The first inquisitor pass (verdict: BLOCK) returned three Critical charges. Charges #1 and #2 identified that W1 (bridge baked content into discovery path) and W2 (expand `--allowedTools`) both rest on unverified claims about `claude-code-action@v1` internals:

- **W1** assumes `$HOME/.claude/{agents,skills,plugins}` is the CLI's discovery path for those resource types. The #245 evidence proves only that `settings.json` goes there. Agent/skill/plugin discovery may use a different loader path. Zero evidence was presented for the broader claim.
- **W2** assumes `Task` is the right tool name for sub-agent dispatch inside the action's non-interactive SDK invocation, and that agents are invocable from that surface at all. Also undemonstrated.

W3 (marker post-processing) survives the cut because it operates entirely on the posted review body using patterns the authoritative gate already proves work. It does not depend on any unverified claude-code-action internals.

**Phase 2 (deferred): bridge baked content and expand allowlist.** Issue [#245](https://github.com/glitchwerks/github-actions/issues/245) tracks the verification work needed before W1 and W2 can be safely planned — specifically, demonstrating from the `@anthropic-ai/claude-code` CLI source or a reproducible invocation that agents/skills/plugins are discovered from `$HOME/.claude/` and that sub-agent dispatch via `Task` is supported in non-interactive mode.

As the inquisitor noted in Charge #7 (sequencing): "W3-leading is exactly what we're now doing" — landing the deterministic post-processor first removes one variable from the W1+W2 verification matrix and protects #242 closure from regressing during that subsequent verification window.

---

## Context

### What is broken

The structured-marker output contract (the `<!-- claude-pr-review-summary-v1` HTML-comment block) is specified in the review overlay's CLAUDE.md as a required LLM output. The LLM's compliance is inconsistent: the shadow gate has reported `marker_missing` on every run since #185 Phase 2 shipped (issue #242). The `APPEND_SYSTEM_PROMPT` position means the instruction is appended rather than authoritative, and turn-budget pressure can truncate the response before the marker is emitted.

### Why W3 fixes it

W3 stops relying on the LLM to emit the marker. A post-processing step, inserted after `claude-code-action@v1` completes, reads the review body already posted by the action and synthesizes the marker deterministically from the prose content using the same severity-counting regex the authoritative gate already uses. The marker is appended to the review comment via a PATCH. If the LLM happened to emit the marker correctly, the step skips (guarded by `grep -qF`).

---

## W3 — Marker synthesis via post-processing

### Severity buckets (from persona spec, verbatim)

`runtime/overlays/review/CLAUDE.md` lines 133–136 define the four required findings fields and their mapping to prose markers:

- `findings.critical` — count of **🔴 Critical (BLOCKING)** findings
- `findings.high` — count of **🟡 High-Priority (MAJOR)** findings
- `findings.medium` — count of **🟢 Medium** findings
- `findings.low` — count of **Nit** findings

These are the authoritative buckets. The four-bucket split is not invented — it is the schema mandated by the persona spec.

### Authoritative gate regex (source of truth)

The severity regex currently lives inline in `pr-review/action.yml` at two locations (line 282, line 333 — identical):

```
grep -E -c '🔴 Critical|Critical \(BLOCKING\)|🟡 High-Priority|\*\*MAJOR\*\*|\*\*BLOCKING\*\*'
```

This is a **single combined blocker class** (critical + high together) used to determine pass/fail. The four-bucket post-processor must map to this same set of patterns. The derivation:

| Bucket | Patterns | Maps to authoritative `BLOCKER_HITS` |
|---|---|---|
| `critical` | `🔴 Critical`, `Critical \(BLOCKING\)`, `\*\*BLOCKING\*\*` | yes |
| `high` | `🟡 High-Priority`, `\*\*MAJOR\*\*` | yes |
| `medium` | `🟢 Medium` | no (advisory only) |
| `low` | `\bNit\b` | no (advisory only) |

Because the gate regex is **inline at two locations** in `action.yml`, extracting it to a shared file is a mandatory W3 deliverable, not a deferred refactor. If W3 ships inline regexes instead, there are now three locations to keep in sync. See Deliverables below.

### Comment-target identification

The inquisitor's Charge #3 flagged that the "PATCH `last by updated_at`" approach is unsafe when `track_progress: true` is set, because progress comments can interleave after the review summary.

Reading `claude-code-action@v1` source (`src/github/operations/comments/create-initial.ts`, `src/entrypoints/run.ts`):

- With `use_sticky_comment: true`, the action creates one comment at job start (the "Claude Code is working…" placeholder) and updates it in-place at job end via an internal `commentId` variable.
- With `track_progress: true`, intermediate tool-call progress is appended to that same comment body — it is not a separate comment. The final review body therefore lives in the same comment the action created at start.
- The `commentId` is tracked internally by the action's `run.ts` `finally` block. **It is not exposed as a step output.** The action's `outputs:` block lists `execution_file`, `branch_name`, `github_token`, `structured_output`, and `session_id` — no `comment_id`.

**Consequence:** W3 cannot obtain the comment ID from `${{ steps.claude-review.outputs.comment_id }}` because that output does not exist. The fallback strategy must be a content-based selector.

**Chosen approach:** Fetch all `github-actions[bot]` comments on the PR, select the one whose body contains the review sentinel (`## ` heading or a known review marker, absent which fall back to the longest bot comment posted after `REVIEW_START_TIME`). This is more robust than a pure temporal selector because it anchors on content. The specific selector is: longest bot comment with `created_at >= REVIEW_START_TIME`, since `track_progress: true` updates (not creates) the sticky comment — the comment's `created_at` predates `REVIEW_START_TIME`, but its `updated_at` is after. Select by `updated_at >= REVIEW_START_TIME AND user.login == "github-actions[bot]"`, picking the single result. If multiple match (edge case: prior run commented right before this run started), take the last by `updated_at`.

This remains an open question until verified against a live run. The implementation PR must enumerate all `github-actions[bot]` comments on a synthetic PR at a known post-`REVIEW_START_TIME` timestamp and confirm exactly one comment matches the selector. If more than one matches, the implementation must add a content-based tie-breaker (e.g., body contains the review's verdict line pattern `## (APPROVE|BLOCK)`).

### Deliverables

**Deliverable A: `pr-review/lib/severity-regex.sh`** — extract the shared severity regex from inline bash into a sourceable shell fragment. Both the authoritative gate step (line 282) and the shadow gate step (line 333) in `action.yml` currently duplicate the same regex string. W3 makes this three copies unless extraction happens first. The file should export four variables:

```bash
# severity-regex.sh — source this file; do not execute directly.
# Provides SEVERITY_BLOCKER_RE (combined) and per-bucket patterns.
SEVERITY_BLOCKER_RE='🔴 Critical|Critical \(BLOCKING\)|🟡 High-Priority|\*\*MAJOR\*\*|\*\*BLOCKING\*\*'
SEVERITY_CRITICAL_RE='🔴 Critical|Critical \(BLOCKING\)|\*\*BLOCKING\*\*'
SEVERITY_HIGH_RE='🟡 High-Priority|\*\*MAJOR\*\*'
SEVERITY_MEDIUM_RE='🟢 Medium'
SEVERITY_LOW_RE='\bNit\b'
```

Both existing gate steps source this file and replace their inline regex with `$SEVERITY_BLOCKER_RE`. The post-processor uses the four per-bucket variables.

**Deliverable B: post-processing step in `pr-review/action.yml`** — inserted between the `Quality gate — post claude-pr-review/quality-gate status` step and the `Quality gate — structured marker (advisory shadow)` step. Illustrative shape (implementation PR must confirm comment selector against a live run):

```yaml
- name: Synthesize structured marker via post-processing
  if: steps.authz.outputs.skip != 'true' && steps.size-check.outputs.skip != 'true' && steps.claude-review.outcome == 'success'
  shell: bash
  env:
    GH_TOKEN: ${{ github.token }}
    GH_REPOSITORY: ${{ github.repository }}
    PR_NUMBER: ${{ github.event.pull_request.number }}
    REVIEW_START_TIME: ${{ env.REVIEW_START_TIME }}
    SEVERITY_REGEX_SH: ${{ github.action_path }}/lib/severity-regex.sh
  run: |
    set -euo pipefail
    # shellcheck source=lib/severity-regex.sh
    source "$SEVERITY_REGEX_SH"
    REPO="$GH_REPOSITORY"

    # Select the bot comment posted/updated during this review run.
    # track_progress: true updates the sticky comment in-place, so created_at
    # may predate REVIEW_START_TIME; filter on updated_at instead.
    COMMENT_JSON=$(gh api "repos/$REPO/issues/$PR_NUMBER/comments?per_page=100" \
      --jq "map(select(.user.login == \"github-actions[bot]\") | select(.updated_at >= \"$REVIEW_START_TIME\")) | sort_by(.updated_at) | last // empty" \
      2>/dev/null || echo "")

    [ -z "$COMMENT_JSON" ] && { echo "No bot comment updated during this review — skipping marker synthesis"; exit 0; }

    BODY=$(printf '%s' "$COMMENT_JSON" | jq -r '.body // ""')
    COMMENT_ID=$(printf '%s' "$COMMENT_JSON" | jq -r '.id')

    # Skip if the LLM already emitted the marker correctly.
    if printf '%s' "$BODY" | grep -qF '<!-- claude-pr-review-summary-v1'; then
      echo "Marker already present in review body — no synthesis needed"
      exit 0
    fi

    # Count per-bucket using sourced regex variables.
    CRITICAL=$(printf '%s' "$BODY" | grep -cE "$SEVERITY_CRITICAL_RE" || true)
    HIGH=$(printf '%s' "$BODY"     | grep -cE "$SEVERITY_HIGH_RE"     || true)
    MEDIUM=$(printf '%s' "$BODY"   | grep -cE "$SEVERITY_MEDIUM_RE"   || true)
    LOW=$(printf '%s' "$BODY"      | grep -cE "$SEVERITY_LOW_RE"      || true)

    MARKER=$(printf '<!-- claude-pr-review-summary-v1\n{"schemaVersion":1,"findings":{"critical":%d,"high":%d,"medium":%d,"low":%d}}\n-->' \
      "$CRITICAL" "$HIGH" "$MEDIUM" "$LOW")

    NEW_BODY=$(printf '%s\n\n%s' "$BODY" "$MARKER")

    gh api "repos/$REPO/issues/comments/$COMMENT_ID" \
      -X PATCH \
      -f body="$NEW_BODY"
    echo "Marker synthesized and appended: critical=$CRITICAL high=$HIGH medium=$MEDIUM low=$LOW"
```

**`parse-marker.sh` compatibility.** The synthesized marker uses the same format as an LLM-emitted marker. The shadow gate step reads whatever is in the comment body and does not distinguish LLM-authored from synthesized. No changes to `parse-marker.sh`.

---

## Open questions

The following questions must be answered before or during the W3 implementation PR. The plan marks each as either *must resolve before PR opens* or *must resolve during implementation*.

**Q1 — Comment selector validation** (must resolve during implementation). The `updated_at >= REVIEW_START_TIME` selector is proposed but not yet verified against a live run. The implementation PR must run against a synthetic PR, enumerate all `github-actions[bot]` comments, and confirm: (a) exactly one comment has `updated_at >= REVIEW_START_TIME`, (b) that comment is the review body, not a progress artifact. If the selector returns zero or more than one, the implementation must document a content-based fallback (e.g., body contains `## ` heading + known review vocabulary).

**Q2 — Non-matching counts: LLM marker vs synthesized** (design decision, resolve before PR opens). If the LLM emits a marker but the `grep -qF` guard confirms it, the post-processor exits early. If the LLM emits a marker with wrong counts (e.g., claims `"critical": 0` but the prose contains `🔴 Critical` findings), the guard exits early and the wrong counts stand. Resolution rule: the `grep -qF` guard should check for marker *presence*, not correctness. For now, presence-check is the correct behavior — the shadow gate will emit `agree:*` / `disagree:*` based on both the marker and the prose scan, surfacing the discrepancy. Actively overwriting a present-but-wrong LLM marker is out of scope for W3.

**Q3 — Regex correctness for non-emoji forms** (verify during implementation). The per-bucket regex splits `**BLOCKING**` into `critical` and `**MAJOR**` into `high`. The authoritative gate combines both into a single blocker class. The split must be verified: a review body containing only `**MAJOR**` should produce `findings.high >= 1` and `findings.critical == 0`, and the shadow gate's `agree:blocking` should fire (because `BLOCKER_HITS` is non-zero). Run manually or in a test PR with a synthetic review body.

---

## Acceptance criteria

- After merge, a real consumer-side review run (verified via siege-web bump using the floating-`v2`-tag pattern) produces `claude-pr-review/quality-gate-shadow = success` (label `agree:clean` or `agree:blocking`) rather than `error / marker_missing`.
- The synthesized marker's `findings.*` counts match the severity-tagged finding counts in the prose review body, verified by inspection on at least one run containing at least one finding.
- When the LLM does emit the marker correctly, the `grep -qF` guard skips re-synthesis — confirmed by a log line `Marker already present in review body — no synthesis needed`.
- The authoritative `quality-gate` pass/fail behavior is unchanged — no regression on a clean review (all-zero marker, `success` status) or a blocking review (`failure` status).
- Both the authoritative gate step and the shadow gate step source `pr-review/lib/severity-regex.sh` — manual diff confirms no inline regex duplication across `action.yml`.
- The marker block schema matches the persona spec: `schemaVersion: 1`, four required `findings` fields, integers >= 0.

---

## Verification strategy

### Dogfooding non-signal

Per CLAUDE.md: PRs opened against this repo run `claude-pr-review` at the released `@v2` tag, not the local branch's composite action changes. The W3 implementation PR's own dogfood run is **non-signal** for verifying marker synthesis. Do not interpret a clean dogfood run as confirmation that W3 works.

### Authoritative verification: siege-web with floated `v2`

1. On the W3 implementation branch, move the floating `v2` tag to point at the branch's HEAD.
2. Open or push a PR in siege-web that triggers `claude-pr-review`.
3. Inspect the Actions run log for: `Marker synthesized and appended: ...` in the synthesis step, and `agree:clean` or `agree:blocking` in the shadow gate step summary.
4. Restore `v2` to `main` HEAD after verification.

**`pull_request_target` trap:** `pull_request_target` resolves the called workflow from the **base branch** of the triggering PR. A siege-web verification PR opened against `main` resolves the reusable workflow at `main` regardless of the head branch. Use the floating-tag approach (step 1 above) — do not open a siege-web PR against `main` expecting it to pick up unreleased composite changes.

---

## Existing artifact cleanup

Verified against live GitHub state as of 2026-05-08.

| Artifact | State | Note |
|---|---|---|
| github-actions PR #244 (`issue-242-option-a`) | ✓ closed 2026-05-08 | Reverted v2.4.2. No action needed. |
| glitchwerks/siege-web PR #305 (v2.4.2 bump) | ✓ closed 2026-05-08 | Merged then closed. No action needed. |
| glitchwerks/siege-web PR #309 (Option A verification) | ✓ closed 2026-05-08 | Result was negative for marker delivery; informed #245 findings. |
| glitchwerks/siege-web issue #308 | ✓ closed | Tracked #309 verification run. |
| glitchwerks/siege-web issue #304 | ✓ closed | Tracked v2.4.1 → v2.4.2 bump. |
| github-actions issue #242 | open | Tracks `marker_missing`. Closes when W3 lands and shadow gate transitions off `error / marker_missing`. |
| github-actions issue #245 | open | W1+W2 verification tracker. Remains open until bridge/allowlist work is verified and implemented in Phase 2. |

---

## Out of scope

- **W1 (bridge baked content into CLI discovery path):** deferred to Phase 2 pending verification that `$HOME/.claude/{agents,skills,plugins}` is the actual discovery path for those resource types. Issue #245 tracks the required verification work.
- **W2 (expand `--allowedTools`):** deferred to Phase 2 pending demonstration that `Task`/`Skill` dispatch is supported in `claude-code-action@v1`'s non-interactive SDK invocation and that baked agents are reachable from that surface.
- **Reclaiming CLI invocation entirely** (running `claude` directly rather than through `claude-code-action@v1`): technically possible, out of scope for recovery.
- **Hardening `runtime-build.yml` smoke tests** to verify CLI discovery at build time: highest-value post-recovery hardening, deferred.
