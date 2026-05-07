# Quality-gate structured-marker contract — implementation plan

**Date:** 2026-05-06
**Phase:** 0 (design lock — no code)
**Issues:** [#185](https://github.com/glitchwerks/github-actions/issues/185) (primary), [#183](https://github.com/glitchwerks/github-actions/issues/183) (partly subsumed), [#223](https://github.com/glitchwerks/github-actions/issues/223) (reproducer)

---

## Status

This plan is the Phase 0 design-lock artifact for issue #185 (Adopt structured marker contract for
quality-gate). It locks the schema format, verdict derivation rule, phasing model, and all eight
open design decisions made during the 2026-05-06 planning conversation. No persona or gate code
changes are made in this PR — those land in Phases 1-4, each as a separate PR. Issues #183 and
#223 are tracked as co-dependents; closures happen in Phase 4.

---

## Background

The current `claude-pr-review/quality-gate` commit status is derived by grepping the review-comment
body for emoji and keyword strings (`🔴 Critical`, `High-Priority`, etc.). This approach is fragile:
the persona may phrase findings in ways the regex does not match, producing a `success` status on a
review that actually identified blocking problems. Issue #223 documents the concrete reproducer: PR
#222's review contained `### Critical Issues Found 🚨` and `**two critical inconsistencies**` in
lowercase, which the gate's then-current regex failed to catch, emitting a false `success`.

Issue #185 proposes three options for replacing the prose-regex approach:

- **Option A** — HTML-comment JSON block at the end of the review body, emitted by the persona
  and parsed by the gate (fully implemented in this repo; no upstream cooperation needed).
- **Option B** — GitHub Actions step outputs surfaced by `anthropics/claude-code-action@v1`
  (requires upstream changes; out of reach for this repo to control).
- **Option C** — A separate artifact (e.g. a JSON file written as a workflow artifact) that the
  gate reads independently of the review body (decouples comment from signal; overkill for current
  needs and adds artifact-lifecycle complexity).

**This plan implements Option A.** Options B and C were not chosen: B depends on upstream
cooperation that cannot be guaranteed, and C introduces a separate artifact lifecycle for a problem
that is cleanly solvable in-repo.

Issue #183 asks for regression-validation of the prose-regex against actual `claude-code-action`
output. The structured-marker plan transforms this concern: once the persona controls the marker
emission, there is no regex to validate — instead, #183's "pin upstream version" principle becomes
"pin the overlay digest that emits the marker." That transformation is finalized at Phase 4; #183
is left open through Phase 3 and closed alongside #185 and #223 in the Phase 4 PR.

---

## Locked design decisions

The table below is authoritative for Phases 1-4. No phase may deviate from these decisions without
a plan amendment that updates this table.

| # | Decision | Lock |
|---|---|---|
| 1 | Schema format | **JSON block in HTML comment**. Sentinel: `claude-pr-review-summary-v1`. Required fields: `schemaVersion` (int, current=1), `findings` (object with `critical`, `high`, `medium`, `low` — all int, all required). NO `verdict` field — gate computes it. |
| 2 | Marker placement | **LAST in review body** (end of comment, just before any auto-generated footer). Persona instruction must reserve final ~2 turns for marker emission. Honor system, not enforced. |
| 3 | Verdict source | **Derived by gate**. Rule: `blocking` if `critical > 0 OR high > 0`, else `clean`. Persona never emits a verdict — only counts. |
| 4 | Shadow-mode mechanism (Phase 2) | **Second commit status** `claude-pr-review/quality-gate-shadow`. Advisory only — does not gate merge. Disagreement criterion: production gate state vs shadow gate state differ for a given commit. |
| 5 | Cutover criterion (Phase 2 → 3) | **≥20 reviews across ≥5 PRs, zero disagreement, zero marker-missing**. Tracked via a weekly aggregator script (Phase 2 deliverable). |
| 6 | Phase 4 marker-missing | **Fail-closed**: `state=failure`, `description="Quality-gate marker missing — re-run review (gh run rerun)"`. Recovery: `gh run rerun <run-id>` OR push empty commit OR admin-merge. NOT a fall-back to prose-regex. |
| 7 | #183 disposition | **Leave open through Phase 3, close at Phase 4** with PR-message reference. #183's "pin upstream version" constraint translates to "pin overlay digest at cutover." |
| 8 | Plan location | **`docs/superpowers/plans/2026-05-06-quality-gate-structured-marker.md`** in this worktree. |

---

## Marker schema (v1)

The persona MUST emit exactly one marker block per review, as the last content before any
auto-generated footer. The block is an HTML comment so it is invisible in rendered Markdown.

### Exact block format

```
<!-- claude-pr-review-summary-v1
{
  "schemaVersion": 1,
  "findings": {
    "critical": 2,
    "high": 1,
    "medium": 4,
    "low": 0
  }
}
-->
```

### Field definitions

| Field | Type | Required | Notes |
|---|---|---|---|
| `schemaVersion` | int | yes | Always `1` for v1. Gate must accept v1 indefinitely for backward compat with archived reviews. Bump on backward-incompatible schema changes. |
| `findings.critical` | int | yes | Count of Critical/BLOCKING findings in the review body. Zero is valid and expected for clean reviews. |
| `findings.high` | int | yes | Count of High-Priority/MAJOR findings. |
| `findings.medium` | int | yes | Count of Medium-Priority findings. |
| `findings.low` | int | yes | Count of Low-Priority/nit findings. |

No `verdict` field is emitted by the persona. The gate derives it.

### Worked example

A review that finds two critical race conditions, one high-priority missing error handler, four
medium-priority style issues, and no nits emits:

```
<!-- claude-pr-review-summary-v1
{
  "schemaVersion": 1,
  "findings": {
    "critical": 2,
    "high": 1,
    "medium": 4,
    "low": 0
  }
}
-->
```

Gate verdict derivation: `critical=2 > 0` → `blocking`. Gate posts
`claude-pr-review/quality-gate` with `state=failure`.

### Verdict rule (gate logic, not persona logic)

```
if findings.critical > 0 OR findings.high > 0:
    verdict = "blocking"   → state=failure
else:
    verdict = "clean"      → state=success
```

`findings.medium` and `findings.low` are informational; they do not affect the verdict.

### Backward compatibility

Future schema versions bump `schemaVersion`. The gate MUST accept `schemaVersion: 1` indefinitely
so that archived review bodies (e.g. on closed PRs) remain parseable for audit and disagreement
tracking purposes.

### Regression fixture (PR #222 / issue #223)

PR #222's review body (issue-comment id `4392784955`) used the heading
`### Critical Issues Found 🚨` and the phrase `**two critical inconsistencies**`. Under the
prose-regex gate this produced a false `success`. Under the structured-marker gate, the patched
persona must emit `critical >= 1` for a review of the same PR, causing the gate to post
`state=failure`. This fixture becomes the Phase 2 regression corpus seed:
`pr-review/tests/marker-cases/pr-222-critical-issues-found.md`.

---

## Phase 0 — Design lock (this PR)

**Deliverable:** This plan file committed to the worktree branch and merged to `main`.
No persona changes, no gate changes, no overlay rebuild.

**Files touched:**
- `docs/superpowers/plans/2026-05-06-quality-gate-structured-marker.md` (this file, new)

**Acceptance criteria:**

- [ ] Plan file is committed to `main` via a merged PR.
- [ ] All eight locked design decisions are present in the plan verbatim.
- [ ] No code, persona, or workflow changes in this PR.
- [ ] PR body references #185, #183, #223 with `Refs` (not `Closes`) keywords.

**Dependencies:** None.

---

## Phase 1 — Persona emits marker

**Deliverable:** The `claude-runtime-review` overlay persona is patched to emit the v1 marker block
at the end of every review. The overlay is rebuilt and the digest pin in
`.github/workflows/claude-pr-review.yml` is updated. Gate behavior is unchanged — the marker is
present in the review body but the gate ignores it until Phase 2.

**Files touched:**

- `runtime/overlays/review/CLAUDE.md` — append a "Structured marker (required)" section under the
  output-contract heading. Must specify: exact block format, required fields, "emit even when zero
  findings," reserve-turn discipline (persona should budget ~2 turns for marker emission at the
  end of the review), single block per review body.
- `runtime/overlays/review/expected.yaml` — no change (no agent or plugin surface change).
- After `runtime-build.yml` produces the new overlay digest:
  - `.github/workflows/claude-pr-review.yml` — repoint `container:` at the new
    `ghcr.io/glitchwerks/claude-runtime-review@sha256:<new-digest>`.
  - `.github/workflows/overlay-smoke.yml` — picks up the new digest automatically via its
    grep-from-workflow-files mechanism; no manual edit needed.

**Design notes:**

- Phase 1 and Phase 2 MUST NOT be combined into a single PR. The gate change (Phase 2) cannot rely
  on the persona producing the marker until the new overlay digest is live and observed in
  production. Combining them would mean the shadow gate fires `marker_missing` on every PR until
  the persona change propagates, polluting the disagreement signal.
- The persona instruction uses "MUST emit" language (not "should"). Marker omission is a persona
  regression, not an acceptable steady state.
- Container `packages: read` permission is already present on `claude-pr-review.yml` per the
  post-#192 hotfix; no permissions edits expected.

**Acceptance criteria:**

- [ ] Persona instruction is unambiguous: required fields, exact comment form, single block per
  review, "always emit even when findings are zero."
- [ ] Overlay rebuild succeeds via `runtime-build.yml`; STAGE 4 inventory match passes (no new
  agents or plugins introduced).
- [ ] New `claude-runtime-review` digest pinned in `claude-pr-review.yml`.
- [ ] After merge, the next 5 PR reviews on this repo each contain the marker block (manual visual
  check; gate still ignores the marker).
- [ ] `overlay-smoke.yml` daily run succeeds with the new digest.

**Dependencies:** Phase 0 merged.

---

## Phase 2 — Shadow-mode gate

**Deliverable:** `pr-review/action.yml` gains a structured-marker parser that runs alongside the
existing prose-regex gate. The marker-derived verdict is posted as a second commit status,
`claude-pr-review/quality-gate-shadow`, which is advisory only and must NOT be required in branch
protection. The original `claude-pr-review/quality-gate` status remains authoritative. A weekly
aggregator workflow surfaces disagreement rate so the Phase 3 cutover criterion can be verified.

**Files touched:**

- `pr-review/action.yml` — add a "Quality gate — structured marker (advisory)" step after the
  existing quality-gate step. The step:
  - Parses the marker block from the already-fetched review body (`$BODY`).
  - Computes `findings` counts or returns `marker_missing` / `marker_invalid` sentinels.
  - Derives verdict from counts per the gate rule (locked decision #3).
  - Posts `claude-pr-review/quality-gate-shadow` with state derived from the marker
    (`success`, `failure`, or `error` for missing/invalid).
  - Writes a step-summary block showing prose-regex result, marker result, and an
    `agree`/`disagree`/`marker_missing` label.
- `pr-review/tests/marker-cases/` (new directory) — fixture files, one per case:
  - `pr-222-critical-issues-found.md` — PR #222's review body (regression case from #223).
    Expected: `critical>=1`, verdict `blocking`.
  - `clean-review.md` — no findings. Expected: all zeros, verdict `clean`.
  - `mixed-severity.md` — at least one finding at each severity. Expected: verdict `blocking`.
  - `marker-missing.md` — pre-marker-era review body (no HTML comment block). Expected:
    sentinel `marker_missing`.
  - `marker-malformed.md` — marker block present but a required field missing or non-numeric.
    Expected: sentinel `marker_invalid` (distinct from `marker_missing`).
- `pr-review/tests/run-marker-cases.sh` — driver script; invokes the parser against each fixture
  and asserts expected outcome. Modeled on `claude-command-router/tests/run-cases.sh`.
- `.github/workflows/test.yml` — invoke `run-marker-cases.sh` alongside the existing router test
  so every PR exercises the marker corpus.
- `.github/workflows/marker-emission-aggregate.yml` — weekly cron (suggested: Mondays 07:00 UTC).
  Queries the last 7 days of `claude-pr-review/quality-gate-shadow` statuses; opens a deduped
  issue titled `Quality-gate shadow: marker_missing events detected` if any `marker_missing` events
  occurred. Provides the data source for verifying the Phase 3 cutover criterion.

**Acceptance criteria:**

- [ ] `pr-review/tests/run-marker-cases.sh` passes for all seeded fixtures, including PR #222's
  review body.
- [ ] On a live PR after merge, both `claude-pr-review/quality-gate` (authoritative) and
  `claude-pr-review/quality-gate-shadow` (advisory) appear in the PR checks list.
- [ ] Shadow status description identifies agreement or disagreement explicitly
  (e.g. `agree:clean`, `disagree:prose=blocking/marker=clean`, `marker_missing`).
- [ ] Branch protection rule for `main` is NOT updated to require the shadow status — verify in
  repo settings before opening the Phase 3 PR.
- [ ] Step-summary on every workflow run shows a readable diff between prose-regex and marker
  results.
- [ ] `marker-emission-aggregate.yml` can be run manually and produces a machine-readable output.

**Dependencies:** Phase 1 merged AND at least 5 PR reviews observed with the marker present
(ensures shadow status has real signal before the aggregator begins tracking).

---

## Phase 3 — Cutover

**Deliverable:** `claude-pr-review/quality-gate` (the authoritative status) is computed from the
structured marker. Prose-regex is retained ONLY as a fallback when the marker is missing or
malformed. The PR body must demonstrate that the cutover criterion has been met.

**Files touched:**

- `pr-review/action.yml` — reorder quality-gate logic: marker parse runs first; if marker is
  present and valid, post authoritative `quality-gate` from marker counts; if marker is missing or
  invalid, fall back to prose-regex AND emit a step-summary warning that identifies the fallback
  path. Shadow-status step removed (cutover criterion already met) or repurposed to record the
  prose-regex result for ongoing regression monitoring.
- `runtime/overlays/review/CLAUDE.md` — if the persona instruction text is strengthened (e.g.
  adding an explicit error-escape-hatch for corner cases), a new overlay digest and digest repoint
  in `claude-pr-review.yml` is required. If the text is unchanged, no rebuild needed.
- `pr-review/tests/marker-cases/` — add a fixture where the marker verdict and the prose-regex
  verdict disagree; assert that the marker wins.

**Cutover criterion (locked decision #5):** ≥20 reviews across ≥5 PRs with zero disagreements
between prose-regex and marker results, AND zero `marker_missing` events in that window. The PR
body must link to the specific `marker-emission-aggregate.yml` workflow runs that demonstrate the
criterion is met. The jq or shell query against the aggregator output that produces the counts
must appear in the PR body so future maintainers can reproduce the measurement.

**Acceptance criteria:**

- [ ] PR body documents that cutover criterion (≥20/≥5/zero-disagree/zero-missing) has been met,
  with links to supporting workflow runs and the measurement query.
- [ ] All Phase 2 fixtures still pass.
- [ ] New disagreement fixture passes (marker wins over prose-regex when they differ).
- [ ] Gate's commit status `description` field identifies which path produced the verdict
  (`marker` vs `fallback:prose-regex`) so post-cutover incidents are diagnosable.
- [ ] Branch protection for `claude-pr-review/quality-gate` continues to function correctly.

**Dependencies:** Phase 2 merged + cutover criterion met and documented.

---

## Phase 4 — Cleanup

**Deliverable:** Prose-regex removed entirely from `pr-review/action.yml`. Gate is fully
marker-driven. Marker-missing fails closed. Closes #185, #183, #223.

**Files touched:**

- `pr-review/action.yml` — delete prose-regex grep step; on `marker_missing` or `marker_invalid`
  post `claude-pr-review/quality-gate` with `state=failure` and description
  `"Quality-gate marker missing — re-run review (gh run rerun)"`.
- `runtime/overlays/review/CLAUDE.md` — remove any "fallback" language; marker emission is
  mandatory with no safety-net path.
- `pr-review/tests/marker-cases/marker-missing.md` — update assertion to verify that
  `state=failure` propagates correctly through the updated code path (was previously `error` in
  Phase 2; Phase 4 uses `failure` per locked decision #6).

**Fail-closed recovery path (operational, not an engineering deliverable):** If the persona fails
to emit the marker due to turn exhaustion or other regression, the gate posts `state=failure` and
the PR cannot merge. Recovery options in descending preference:

1. `gh run rerun <run-id>` — fresh turn budget, fresh review; sticky comment is overwritten.
2. Push an empty commit to the PR branch — triggers a new review run.
3. Admin-merge via branch-protection bypass — last resort; should be logged as an incident.

These are documented operator paths, not engineering workarounds. The fail-closed posture is
intentionally strict at Phase 4; the Phase 2/3 shadow period exists precisely so the operator
has confidence the persona is reliable before this strictness is enforced.

**#183 transformation:** #183 originally asked for regex validation against actual
`claude-code-action` output. The structured-marker plan transforms this concern: with the persona
controlling marker emission, there is no prose regex to validate. The "pin upstream version"
principle from #183 becomes "pin the overlay digest at cutover" — implemented throughout Phases
1-3. #183 is closed by this PR as resolved-by-structured-marker.

**Acceptance criteria:**

- [ ] Prose-regex grep (`grep -E -c`) no longer present in `pr-review/action.yml`.
- [ ] On `marker_missing`, gate posts `state=failure` with the exact description from locked
  decision #6: `"Quality-gate marker missing — re-run review (gh run rerun)"`.
- [ ] All Phase 2 and Phase 3 fixtures still pass under the updated assertions.
- [ ] Branch protection for `claude-pr-review/quality-gate` continues to function
  (`state=failure` satisfies required-check enforcement as expected).
- [ ] K=10 consecutive marker-authoritative runs across ≥3 distinct PRs since Phase 3 cutover
  documented in PR body.
- [ ] Closes #185 (primary issue).
- [ ] Closes #183 (pin-upstream becomes pin-overlay-digest; prose-regex removed).
- [ ] Closes #223 (PR #222 regression reproducer; Phase 2 fixture confirmed blocking verdict).

**Dependencies:** Phase 3 merged + K=10 consecutive runs documented.

---

## Out of scope

The following are explicitly excluded from this plan and must not be folded into Phases 1-4:

- **Issue #182** (quality-gate fails open on transient `gh api` error) — orthogonal to the
  marker contract. Transient-API hardening has independent risk/benefit trade-offs and a separate
  failure mode; it warrants its own plan.
- **Multi-bot collision** — the case where two bots both post review comments and the gate cannot
  determine which structured marker is authoritative is not addressed here. The current system has
  a single reviewer persona; multi-bot scenarios are deferred until that assumption changes.
- **Upstream cooperation with `anthropics/claude-code-action`** — Option A is fully implemented
  in this repo's overlay persona and gate logic. No PRs to the upstream action are needed or
  planned.
- **Expanding the gate beyond `pr-review`** — `lint-failure`, `fix`, and `explain` overlays are
  not in scope. If those actions gain a quality-gate concept in the future, a separate plan is
  required.
- **Refactoring the gate into a separate composite action** — the gate logic stays in
  `pr-review/action.yml` throughout all four phases.

---

## Open questions

_All seven design questions from the planner draft are now locked (see "Locked design decisions"
above). This section is intentionally empty at Phase 0._

If new questions surface during Phases 1-4, append them here with a `[Phase N — opened YYYY-MM-DD]`
prefix and resolve them before the relevant phase PR opens.

---

## Decision log

**Phase 0 — Design locked 2026-05-06**
All eight design decisions were made during a planning conversation on 2026-05-06. The planner
draft (`C:/Users/chris/.claude/state/2026-05-06-quality-gate-structured-marker.md`) had seven
open questions; those were resolved and two additional decisions were locked (Phase 4 fail-closed
behavior and plan file location). Option A (HTML-comment JSON block) was selected over Option B
(upstream action step outputs) and Option C (separate artifact). Issue #223 / PR #222 was
designated as the canonical regression reproducer for Phase 2's fixture corpus. #183's scope
was reframed from "validate prose-regex" to "pin overlay digest at cutover."

_(Subsequent phases: append one entry per merged PR with the PR number, merge date, and a one-line
summary of any decisions made or questions resolved during implementation.)_
