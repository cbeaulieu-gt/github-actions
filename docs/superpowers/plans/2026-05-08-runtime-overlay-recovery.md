# 2026-05-08 — Marker Synthesis via Post-Processing (Phase 1 of runtime overlay recovery)

**Status: DRAFT — addressed round-2 inquisitor charges**

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

### W3's fundamental limitation — persona-tagging dropout

W3 reads only what the persona wrote. The root cause of `marker_missing` is that the persona follows the `APPEND_SYSTEM_PROMPT` instruction unreliably. If the persona is ignored badly enough to omit the marker, it may also be ignored badly enough to omit `🔴 Critical` / `**MAJOR**` severity tagging on real blocker findings. In that case W3 produces `findings.critical=0, high=0` — the shadow gate posts `agree:clean`, #242 closes, and a regression in persona authority becomes invisible.

**W3 does not detect or prevent persona-tagging dropout.** It converts `marker_missing` errors to synthesized markers, but a synthesized `0/0/0/0` marker on a substantive review body may indicate the persona dropped severity tagging rather than a genuinely clean review.

**Defensive synthesis with corroboration (Option A).** To bound this failure mode, W3 will refuse to post a `0/0/0/0` synthesized marker unless an independent corroboration signal confirms the LLM performed substantive analysis. The corroboration check: if the diff has at least one changed line (a non-trivial review context) AND the synthesized counts are all zero AND no recognized section headers from the persona's required structure are present in the body (e.g., `### Findings` or `### Verdict`), then W3 should post `state=error` with description `synthesis_skipped:no_corroboration` rather than a misleading clean marker.

Concretely, a `0/0/0/0` clean synthesis is **accepted** when any of the following holds:
- The diff has zero changed lines (trivially empty PR — genuinely clean is expected)
- The review body contains at least one recognized persona section header (`### Findings` or `### Verdict`)
- The review body length is above 500 characters (implies the LLM wrote substantive prose even if un-tagged)

If none of these hold, synthesis is skipped and an error status is posted. This makes the failure mode visible to the gate operator rather than silently laundering it through the shadow gate.

**Signal independence:** The body-length check is independent of persona compliance — the LLM produces verbose output even when ignoring format instructions. The section-header check correlates with persona compliance (if the persona is ignored badly enough to drop severity emojis, it may also be ignored badly enough to drop `### Findings`/`### Verdict` headers). The headers remain a useful but secondary signal; the corroboration check accepts EITHER (A OR B) because we want to catch the case where the LLM produces a non-empty review without standard structure. The body-length check is the primary independent corroborator. An implementer must not tighten the section-header check later thinking it is load-bearing — it is not.

Option B (periodic monitoring scan) was considered and rejected for this plan: a separate cron job that audits recent reviews for zero-count prose is useful long-term but is separate work that may not ship. Defensive synthesis is local to W3's PR and ships atomically with the fix.

**Acceptance criteria implication.** On at least one real consumer-side run that contains findings, a human must inspect that the synthesized counts match the prose severity tags. This manual spot-check is a required acceptance criterion — not optional verification — because it is the only way to confirm the persona did not silently drop severity tagging on that run.

---

## Phase 0 — Verification spike (must complete before Phase 1 opens)

The comment-target selector is the load-bearing mechanism for W3. An implementer who opens the implementation PR before validating the selector will either discover it is wrong mid-PR or expand the PR to include the spike inline. Neither outcome is acceptable.

### Spike scope

Run the selector against real PR reviews in siege-web and confirm the comment-target behavior.

**Spike protocol:**

1. Run the selector against ≥ 5 real PR reviews on siege-web or this repo's dogfood. Capture each trial's result (which comment was selected, was it the right one).
2. Run at least one trial that exercises a `gh run rerun` overlap (kick off rerun while a prior run's progress comment is still updating).
3. Run at least one trial with a manually pre-pushed bot comment that has `updated_at >= REVIEW_START_TIME` from a prior run, simulating the prior-run sticky race.
4. Spike passes only if 100% of trials select the right comment. A single false-positive selector hit fails the spike.
5. Document each trial's result in the spike comment on #246.

For each trial, the core verification query is:
```bash
gh api "repos/glitchwerks/siege-web/issues/$PR_NUMBER/comments?per_page=100" \
  --jq '[.[] | select(.user.login == "github-actions[bot]")] | sort_by(.updated_at)'
```
Record: how many `github-actions[bot]` comments exist, their `created_at` vs `updated_at` timestamps, and which one is the review body. Confirm that exactly one comment satisfies `updated_at >= REVIEW_START_TIME`.

**Prerequisites and the `pull_request_target` caveat.** The verification must use the floating-tag approach — opening a siege-web PR against `main` resolves the reusable workflow from the base branch at `main` regardless of the head branch. A `pull_request_target` trigger resolves the called workflow from the base, not the head; this is the same trap siege-web #309 demonstrated. Float `v2` to the spike branch before opening the synthetic PR.

### Spike checkpoint

The spike's output is a written finding posted as a comment on PR #246. It must state one of:

- **Selector confirmed**: exactly one `github-actions[bot]` comment matches `updated_at >= REVIEW_START_TIME`; it is the review body; no additional progress comments match. All ≥ 5 trials passed with 100% selection accuracy.
- **Selector revised**: the selector does not reliably return exactly one match under [documented scenario]. The revised selector design is: [alternative]. The implementation PR must use the revised design.

The spike comment must explicitly state "spike passes" or "spike fails" and list each trial's result. A vague "looks good" is not sufficient sign-off.

**No implementation PR (Phase 1) may open until this comment exists on #246.**

If the selector cannot be made race-free with content + time + author alone, the spike must propose an alternative: write the comment ID to `$GITHUB_ENV` immediately after a known-fresh comment is created in a setup step, or coordinate via the action's existing outputs even if the API is undocumented.

---

## Phase 1 — W3 implementation (opens after Phase 0 checkpoint)

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

The inquisitor's Charge #3 (round 1) flagged that the "PATCH `last by updated_at`" approach is unsafe when `track_progress: true` is set, because progress comments can interleave after the review summary.

Reading `claude-code-action@v1` source (`src/github/operations/comments/create-initial.ts`, `src/entrypoints/run.ts`):

- With `use_sticky_comment: true`, the action creates one comment at job start (the "Claude Code is working…" placeholder) and updates it in-place at job end via an internal `commentId` variable.
- With `track_progress: true`, intermediate tool-call progress is appended to that same comment body — it is not a separate comment. The final review body therefore lives in the same comment the action created at start.
- The `commentId` is tracked internally by the action's `run.ts` `finally` block. **It is not exposed as a step output.** The action's `outputs:` block lists `execution_file`, `branch_name`, `github_token`, `structured_output`, and `session_id` — no `comment_id`.

**Consequence:** W3 cannot obtain the comment ID from `${{ steps.claude-review.outputs.comment_id }}` because that output does not exist. The fallback strategy must be a content-based selector.

**Chosen approach:** Select by `updated_at >= REVIEW_START_TIME AND user.login == "github-actions[bot]"`, picking the single result. If multiple match (edge case: prior run commented right before this run started), take the last by `updated_at`.

**Selector race risk (round-2 charge).** The two existing gate steps in `action.yml` (lines 282 and 333) currently select via `sort_by(.updated_at) | last` with no `REVIEW_START_TIME` filter. W3 adds the time filter. Three failure modes exist:

1. **Replication lag:** W3 PATCHes comment A; the shadow gate step fetches stale state (without the marker) and emits `marker_missing`.
2. **Prior-run stickies:** a sticky comment from a previous run has an `updated_at` inside the current window if the prior run finished very recently.
3. **Rerun overlap:** `gh run rerun` launches a new run before the prior run's sticky has aged out.

**Remediation (mandatory in the implementation PR):** Extract the comment-selection logic into a single helper sourced by all three steps (synthesis and both gates). Pin to a comment ID once selected by writing it to `$GITHUB_ENV`, so the shadow gate uses the same comment ID W3 already PATCHed — avoiding the replication-lag race. The Phase 0 spike must characterize whether race scenarios (b) and (c) are observed in practice; if they are, the implementation PR's selector design must address them before opening.

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

**Deliverable B: post-processing step in `pr-review/action.yml`** — inserted between the `Quality gate — post claude-pr-review/quality-gate status` step and the `Quality gate — structured marker (advisory shadow)` step. The comment ID selected here must be written to `$GITHUB_ENV` so the shadow gate step reuses it rather than re-selecting independently. Illustrative shape (implementation PR must confirm comment selector against Phase 0 spike output before finalizing):

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

    # Pin comment ID for the shadow gate step to avoid replication-lag race.
    echo "SYNTHESIS_COMMENT_ID=$COMMENT_ID" >> "$GITHUB_ENV"

    # Skip if the LLM already emitted the marker correctly.
    if printf '%s' "$BODY" | grep -qF '<!-- claude-pr-review-summary-v1'; then
      echo "Marker already present in review body — no synthesis needed"
      exit 0
    fi

    # Count per-bucket using grep -oE | wc -l (counts matches, not lines).
    # grep -cE would count lines; a line with two severity tokens counts once, not twice.
    CRITICAL=$(printf '%s' "$BODY" | grep -oE "$SEVERITY_CRITICAL_RE" | wc -l || true)
    HIGH=$(printf '%s' "$BODY"     | grep -oE "$SEVERITY_HIGH_RE"     | wc -l || true)
    MEDIUM=$(printf '%s' "$BODY"   | grep -oE "$SEVERITY_MEDIUM_RE"   | wc -l || true)
    LOW=$(printf '%s' "$BODY"      | grep -oE "$SEVERITY_LOW_RE"      | wc -l || true)

    # Defensive synthesis: refuse to post 0/0/0/0 unless a corroboration signal
    # confirms the LLM performed substantive analysis.
    # A 0/0/0/0 marker on a trivial (zero-diff) PR is legitimate.
    # A 0/0/0/0 marker on a non-trivial PR with no persona structure is suspect:
    # the persona may have dropped severity tagging entirely, which would make
    # the shadow gate post agree:clean on what is actually a persona dropout.
    if [ "$CRITICAL" -eq 0 ] && [ "$HIGH" -eq 0 ] && [ "$MEDIUM" -eq 0 ] && [ "$LOW" -eq 0 ]; then
      BODY_LEN=$(printf '%s' "$BODY" | wc -c)
      HAS_SECTION=$(printf '%s' "$BODY" | grep -cE '^### (Findings|Verdict)' || true)
      # Diff line count requires the PR diff context; approximate via review body length.
      # Accept 0/0/0/0 if: body is substantive (>500 chars) OR has persona section headers.
      # Reject (post error) if body is short AND has no section headers — likely persona dropout.
      if [ "$BODY_LEN" -lt 500 ] && [ "$HAS_SECTION" -eq 0 ]; then
        echo "synthesis_skipped:no_corroboration — zero counts but no persona structure detected"
        gh api "repos/$REPO/statuses/$(gh api repos/$REPO/pulls/$PR_NUMBER --jq .head.sha)" \
          -X POST \
          -f state=error \
          -f description='synthesis_skipped:no_corroboration' \
          -f context='claude-pr-review/quality-gate-shadow' \
          -f target_url="$GITHUB_SERVER_URL/$REPO/pull/$PR_NUMBER" 2>/dev/null || true
        exit 0
      fi
    fi

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

**Q1 — Comment selector validation** (must resolve before PR opens — via Phase 0 spike). The `updated_at >= REVIEW_START_TIME` selector is proposed but not yet verified against a live run. Phase 0 is the checkpoint. No implementation PR opens until the spike finding is posted on #246.

**Q2 — Non-matching counts: LLM marker vs synthesized** (design decision, resolve before PR opens). If the LLM emits a marker but the `grep -qF` guard confirms it, the post-processor exits early. If the LLM emits a marker with wrong counts (e.g., claims `"critical": 0` but the prose contains `🔴 Critical` findings), the guard exits early and the wrong counts stand. Resolution rule: the `grep -qF` guard should check for marker *presence*, not correctness. For now, presence-check is the correct behavior — the shadow gate will emit `agree:*` / `disagree:*` based on both the marker and the prose scan, surfacing the discrepancy. Actively overwriting a present-but-wrong LLM marker is out of scope for W3.

**Q3 — Regex correctness for non-emoji forms** (verify during implementation). The per-bucket regex splits `**BLOCKING**` into `critical` and `**MAJOR**` into `high`. The authoritative gate combines both into a single blocker class. The split must be verified: a review body containing only `**MAJOR**` should produce `findings.high >= 1` and `findings.critical == 0`, and the shadow gate's `agree:blocking` should fire (because `BLOCKER_HITS` is non-zero). Run manually or in a test PR with a synthetic review body.

---

## Acceptance criteria

- After merge, a real consumer-side review run (verified via siege-web bump using the floating-`v2`-tag pattern) produces `claude-pr-review/quality-gate-shadow = success` (label `agree:clean` or `agree:blocking`) rather than `error / marker_missing`.
- The synthesized marker's `findings.*` counts match the severity-tagged finding counts in the prose review body, **verified by human spot-check** on at least one run containing at least one finding. This check is mandatory — not optional — because it is the only direct signal that the persona did not silently drop severity tagging on that run.
- When the LLM does emit the marker correctly, the `grep -qF` guard skips re-synthesis — confirmed by a log line `Marker already present in review body — no synthesis needed`.
- The authoritative `quality-gate` pass/fail behavior is unchanged — no regression on a clean review (all-zero marker, `success` status) or a blocking review (`failure` status).
- Both the authoritative gate step and the shadow gate step source `pr-review/lib/severity-regex.sh` — manual diff confirms no inline regex duplication across `action.yml`.
- The marker block schema matches the persona spec: `schemaVersion: 1`, four required `findings` fields, integers >= 0.
- When defensive synthesis fires (short body, no persona section headers, all-zero counts), the shadow gate posts `state=error` with `synthesis_skipped:no_corroboration` rather than `agree:clean`.
- All three comment-selector invocations (synthesis step + both gate steps) use the same comment ID, pinned via `$GITHUB_ENV` after the synthesis step selects it.

---

## Verification strategy

### Dogfooding non-signal

Per CLAUDE.md: PRs opened against this repo run `claude-pr-review` at the released `@v2` tag, not the local branch's composite action changes. The W3 implementation PR's own dogfood run is **non-signal** for verifying marker synthesis. Do not interpret a clean dogfood run as confirmation that W3 works.

### Authoritative verification: siege-web with floated `v2`

1. On the W3 implementation branch, move the floating `v2` tag to point at the branch's HEAD.
2. Open or push a PR in siege-web that triggers `claude-pr-review`.
3. Inspect the Actions run log for: `Marker synthesized and appended: ...` in the synthesis step, and `agree:clean` or `agree:blocking` in the shadow gate step summary.
4. For a run containing findings: manually compare the synthesis log line's counts against the prose severity tags in the review body. They must match.
5. Restore `v2` to `main` HEAD after verification.

**`pull_request_target` trap:** `pull_request_target` resolves the called workflow from the **base branch** of the triggering PR. A siege-web verification PR opened against `main` resolves the reusable workflow at `main` regardless of the head branch. Use the floating-tag approach (step 1 above) — do not open a siege-web PR against `main` expecting it to pick up unreleased composite changes.

---

## Existing artifact cleanup

**Verify at impl-PR-open time.** This table reflects state at plan-approval time. The implementer of W3's PR must re-verify each row against current GitHub state before relying on the table's "to close" / "✓ closed" assertions — re-run the commands listed in the footer below.

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

**Re-verify commands (run at impl-PR-open time):**

```bash
gh pr view 244 --repo glitchwerks/github-actions --json state,closedAt
gh pr view 305 --repo glitchwerks/siege-web --json state,closedAt,mergedAt
gh pr view 309 --repo glitchwerks/siege-web --json state,closedAt
gh issue view 304 --repo glitchwerks/siege-web --json state
gh issue view 308 --repo glitchwerks/siege-web --json state
gh issue view 242 --repo glitchwerks/github-actions --json state
gh issue view 245 --repo glitchwerks/github-actions --json state
```

---

## Out of scope

- **W1 (bridge baked content into CLI discovery path):** deferred to Phase 2 pending verification that `$HOME/.claude/{agents,skills,plugins}` is the actual discovery path for those resource types. Issue #245 tracks the required verification work.
- **W2 (expand `--allowedTools`):** deferred to Phase 2 pending demonstration that `Task`/`Skill` dispatch is supported in `claude-code-action@v1`'s non-interactive SDK invocation and that baked agents are reachable from that surface.
- **Reclaiming CLI invocation entirely** (running `claude` directly rather than through `claude-code-action@v1`): technically possible, out of scope for recovery.
- **Hardening `runtime-build.yml` smoke tests** to verify CLI discovery at build time: highest-value post-recovery hardening, deferred.
- **Persona-tagging dropout detection:** W3 converts `marker_missing` to synthesized markers but cannot distinguish "LLM reviewed and found nothing" from "LLM dropped severity tagging entirely." Defensive synthesis (Option A above) bounds the failure mode at the `0/0/0/0` boundary; exhaustive tagging-dropout detection is a separate concern and out of scope for this plan.
