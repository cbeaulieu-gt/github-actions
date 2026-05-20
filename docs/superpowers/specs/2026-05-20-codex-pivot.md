---
title: Codex Pivot — Dual-Surface (App for Review, codex-action for Write-Side)
revision: 2
supersedes_conceptual: v1 (this same file, prior revision — no PR ever landed)
touches:
  # Workflows — migrate (write-side; openai/codex-action)
  - .github/workflows/claude-apply-fix.yml
  - .github/workflows/claude-lint-failure.yml
  - .github/workflows/claude-ci-failure.yml
  - .github/workflows/claude-tag-respond.yml
  - .github/workflows/claude-lint-fix.yml
  - .github/workflows/ci-failure.yaml
  - .github/workflows/apply-fix.yml
  # Workflows — RETIRE entirely (handled by Codex GitHub App, no replacement file)
  - .github/workflows/claude-pr-review.yml
  # Workflows — new gate (one new file)
  - .github/workflows/codex-gate.yml
  # Workflows — runtime tree (delete all)
  - .github/workflows/overlay-smoke.yml
  - .github/workflows/runtime-build.yml
  - .github/workflows/runtime-check-private-freshness.yml
  - .github/workflows/runtime-prune-pending.yml
  - .github/workflows/runtime-rollback.yml
  - .github/workflows/marker-emission-aggregate.yml
  # Composite actions — RETIRE (App-handled)
  - pr-review/action.yml
  - pr-review/lib/severity-regex.sh
  # Composite actions — RETIRE (verb router collapses)
  - tag-claude/action.yml
  - claude-command-router/action.yml
  - check-auth/action.yml
  # Composite actions — migrate/rename
  - apply-fix/action.yml
  - lint-failure/action.yml
  - lint-diagnose/action.yml
  - lint-apply/action.yml
  # Runtime tree (delete)
  - runtime/**
  # Consumer-facing surface (rewrite for v3)
  - examples/**
  - docs/consumer-onboarding.md
  # Docs and consumer surface
  - CLAUDE.md
  - README.md
  - AGENTS.md
  - docs/superpowers/specs/2026-04-21-ci-claude-runtime-design.md
  - docs/superpowers/plans/2026-04-22-ci-claude-runtime.md
skills_relevant:
  - github-actions
  - hook-authoring
---

# Codex Pivot — Spec (Rev 2)

**Epic:** #273  •  **Milestone:** `codex-pivot` (#10)  •  **Date:** 2026-05-20

> **Rev 2 note.** This revision supersedes the v1 architectural assumption that
> all five workflows must migrate to `openai/codex-action`. Spike #275 confirmed
> the Codex GitHub App's subscription path works end-to-end on `glitchwerks/github-actions`,
> which restructures the migration into two surfaces (App for review; action for write-side).
> Rev 2 also addresses 4 BLOCKING / 5 CONCERN / 3 NIT findings from project-reviewer on v1.

---

## 1. Overview

Replace this repo's CI Claude surface with a **dual-surface Codex architecture:**

- **PR review** → the **Codex GitHub App** (`chatgpt-codex-connector[bot]`),
  configured cloud-side. No workflow file. No composite action. No in-repo
  secret. Subscription-covered (ChatGPT Plus / Pro / Business / Edu / Enterprise).
- **Write-side workflows** (apply-fix, lint-failure, ci-failure, tag-respond) →
  `openai/codex-action@v1` with `OPENAI_API_KEY`. API-billed; per-token spend.

The entire `runtime/` Docker overlay tree (base + 3 overlays + 6 support workflows)
retires. The local dev loop (Claude Code in the IDE) is unaffected.

Success criterion (verbatim from user): **"context-aware reviewing"** — confirmed
achievable under the App path. Spike #275 observed Codex running
`git ls-files | rg 'codex-(pivot|evaluation)\.md'` from inside its sandbox to
verify a reference claim ([spike #275 closing comment](https://github.com/glitchwerks/github-actions/issues/275), fetched 2026-05-20).
The App has full repo-tree access during review, not diff-only.

## 2. Drivers

1. **OAuth deprecation deadline ~2026-06-20.** Anthropic is deprecating OAuth for
   non-interactive use; `CLAUDE_CODE_OAUTH_TOKEN` stops working ~30 days from
   2026-05-20. Hard cutover deadline.
2. **Quality-gate fragility.** Prose-regex severity matching (#271) has produced
   self-blocking PRs (#270). The App's structured review state replaces regex
   entirely.
3. **Cost.** The subscription covers the review surface at zero marginal cost.
   Pre-Rev-2 estimate (whole surface on `openai/codex-action`): ~$232/mo on
   gpt-5.2-codex assuming pr-review volume on all five workflows. Actual Rev 2
   spend is bounded to the four write-side workflows, all of which are failure-
   triggered or on-demand (low volume) — likely <$50/mo. **unverified:** actual
   monthly spend will only be measurable post-cutover.
4. **Cross-model review.** Claude Code authors locally; Codex/GPT-5.x reviews in
   CI. Cross-model review catches a different failure set than same-model self-
   review.

## 3. Codex Surface Inventory — Spike-Verified Facts

Spike #275 ([closing comment](https://github.com/glitchwerks/github-actions/issues/275), fetched 2026-05-20) verified the following on real
`chatgpt-codex-connector[bot]` reviews against PR #276:

| Fact | Source |
|---|---|
| Bot identity is `chatgpt-codex-connector[bot]`, `author_association: NONE` | [PR #276 review](https://github.com/glitchwerks/github-actions/pull/276) (fetched 2026-05-20) |
| Subscription tier (ChatGPT Plus) is sufficient for org-owned repo review | Spike #275 + PR #276 |
| Review state on a P2-only finding is `COMMENTED` (not `CHANGES_REQUESTED`) | PR #276 |
| Severity surfaced as P0/P1/P2/P3 markdown shield-image badges + prose | PR #276 |
| Context-aware: Codex runs shell against full repo tree in its sandbox | Spike #275 closing comment |
| Triggers confirmed: PR open, draft → ready-for-review, `@codex review` comment | Codex disclosure footer on PR #276 |
| `synchronize`-event auto-trigger | **unverified:** not in Codex's disclosed trigger list; observe during shadow mode |
| `CHANGES_REQUESTED` threshold (which severity emits which state) | **unverified:** undocumented; observe during shadow mode |
| Review-depth modes (default vs exhaustive): exhaustive ~2× slower, identical 1-finding output on the spike PR | Spike #275 |
| Default-vs-exhaustive finding-density delta on real diffs | **unverified:** synthetic stimulus inconclusive; resolved by shadow-mode observation |

For descriptive Phase 0 research (cookbook patterns, action inputs, pricing),
see `docs/superpowers/research/2026-05-20-codex-evaluation.md` (PR #277). The
spec retains only the load-bearing facts.

### 3.1 `openai/codex-action@v1.8` — write-side action

Currently published at **`v1.8`**; `@v1` floating tag tracks the v1 major.
**Pinning policy.** `openai/codex-action` is pinned at `@v1` as a starting
point. If a breaking change is observed in the first 90 days post-cutover
(defined: any composite-action behavior regression, input/output schema change,
or sandbox-mode default flip), promote the pin to a SHA digest captured at the
last-known-good run. SHA-pinning of `actions/checkout`, `actions/create-github-app-token`,
and other third-party actions in the same composite action is a separate concern
tracked under sub-issue #L (or file a new sub-issue if #L doesn't cover it) and
is NOT a prerequisite for the `@v1` major-tag pin.

Key inputs (unchanged from v1 spec, retained verbatim for reference):

| Input | Purpose |
|---|---|
| `openai-api-key` | Secret for Responses API proxy (required) |
| `prompt` / `prompt-file` | Inline or file-based instructions |
| `sandbox` | `workspace-write` \| `read-only` \| `danger-full-access` |
| `output-schema` / `output-schema-file` | JSON Schema for structured output |
| `output-file` | Path Codex writes its final message to |
| `model`, `effort` | Model selection and reasoning effort |
| `codex-args` | Passthrough flags to `codex exec` |
| `safety-strategy` | `drop-sudo` (default) \| `unprivileged-user` \| `read-only` \| `unsafe` |
| `allow-users`, `allow-bots`, `allow-bot-users` | Built-in authorization gating |

Source: [openai/codex-action README](https://github.com/openai/codex-action) (fetched 2026-05-20).

The action **does not post PR comments itself** — workflows consume
`final-message` or read `output-file` and post via `actions/github-script` or
`gh pr comment` ([Codex GitHub Action docs](https://developers.openai.com/codex/github-action), fetched 2026-05-20).

## 4. Architecture Decision — Dual Surface

**Decision:** **Codex GitHub App for PR review; `openai/codex-action` for write-side workflows.**

Reasoning chain:

1. The App is subscription-covered. Cost on the review surface drops to $0 marginal.
2. The App's cloud sandbox provides full-repo context-aware reviewing without
   any CI plumbing on our side (no diff-walk, no severity regex, no
   `track_progress`, no overlay images).
3. The App ships severity filtering, formatting, comment-posting, and re-review
   on `@codex review` natively — none of this needs to be re-implemented.
4. Write-side workflows can't use the App (it only reviews; it doesn't apply
   patches or post diagnoses). They need the action with an API key.
5. Coexistence is supported: nothing in OpenAI's docs prohibits the App
   reviewing a PR while a workflow_call-shaped action job also runs against the
   same repo ([Codex GitHub integration](https://developers.openai.com/codex/integrations/github), fetched 2026-05-20).

**Trade-off accepted:** the user pays for ChatGPT subscription **and**
`OPENAI_API_KEY` consumption. Mitigated by the four write-side workflows being
low-volume (failure-triggered / on-demand).

**Reviewer BLOCKING #1 resolved:** v1's `codex-review-gate.yml` race condition
(unfiltered `pull_request_review` listener could fire on any reviewer's comment,
not Codex's) is **moot under the App path** because we no longer write a gate
workflow that listens for review events. The App's own review state is read by
branch protection directly — see § 7.

## 5. Workflow-by-Workflow Migration Plan

### 5.1 `pr-review` — RETIRE entirely

**No replacement workflow file. No composite action.** The Codex GitHub App,
configured in `chatgpt.com/codex/settings/code-review` with **Automatic reviews
ON** for `glitchwerks/github-actions`, handles PR review end-to-end.

**Files deleted:**

- `.github/workflows/claude-pr-review.yml`
- `pr-review/action.yml`
- `pr-review/lib/severity-regex.sh`

**Configuration carried over:** the inline prompt in `pr-review/action.yml` and
the repo-specific review guidance is translated into a top-level `AGENTS.md`
file (Codex reads the nearest `AGENTS.md` to each changed file — [source](https://developers.openai.com/codex/integrations/github), fetched 2026-05-20).

### 5.2 `apply-fix` → `codex-apply-fix` (migrate; **contract preserved**)

**Reviewer BLOCKING #2 resolution.** `codex-apply-fix/` keeps the current
contract: **the caller workflow passes a pre-produced `fix_diff` input.** The
composite action validates the diff against protected paths and applies it.
The agent (Codex) is **not** invoked inside `codex-apply-fix/`; Codex is invoked
upstream (in `codex-lint-failure/`, `codex-ci-failure/`, etc.) and **those**
workflows produce the diff that they pass into `codex-apply-fix/`.

This preserves the v2 consumer-facing contract:

- `apply-fix/` (today) takes `fix_diff` as input.
- `codex-apply-fix/` (Rev 2) takes `fix_diff` as input.
- **Breaking change for external consumers:** the action **path** changes
  (`glitchwerks/github-actions/apply-fix@v2` → `glitchwerks/github-actions/codex-apply-fix@v3`)
  and the workflow filename changes (`claude-apply-fix.yml` → `codex-apply-fix.yml`).
  The **input/output schema is unchanged.** See § 10 for migration notes.

**Legacy `apply-fix.yml`** (the `workflow_dispatch` manual-trigger wrapper) is
**deleted**, not migrated. The user can re-derive a manual path on demand from
the new `codex-apply-fix.yml` (which is `workflow_call`-shaped — invoke it from
a local `workflow_dispatch` shim if needed).

### 5.3 `lint-failure` → `codex-lint-failure` (migrate)

Same shape as today: fetches failed lint logs, invokes the agent for
diagnosis, optionally auto-applies a fix when `auto_apply: true`. Replace the
`claude-code-action@v1` step with `openai/codex-action@v1` using
`sandbox: workspace-write` and a verb-specific prompt file.

**Reviewer CONCERN #9 (sandbox vs `/tmp/` log pre-writes):** the existing flow
writes the failed-lint logs to `/tmp/lint_logs.txt` before invoking the agent.
Under `openai/codex-action` with `sandbox: workspace-write`, Codex can read
files inside the workspace; `/tmp/` is outside the workspace. **Resolution:**
move log pre-writes to `${{ github.workspace }}/.tmp/lint_logs.txt` (matches
CLAUDE.md § Agent Scratch / Temp Files anyway) and reference that path in the
prompt. Carry this same fix into 5.4 and 5.5.

**Legacy `claude-lint-fix.yml`** (two-job `lint-diagnose` + `lint-apply`) is
**deleted**. Composite action directories `lint-diagnose/` and `lint-apply/`
are deleted. The unified `codex-lint-failure/` is the single supported shape.

### 5.4 `ci-failure` → `codex-ci-failure` (migrate)

Both `claude-ci-failure.yml` (container-pinned) and legacy `ci-failure.yaml`
collapse to a single `codex-ci-failure.yml` reusing `codex-lint-failure/` (per
today's pattern where both reuse `lint-failure/`).

**Reviewer NIT #10 resolution (direct-commit vs PR-open):** **keep direct-commit
semantics.** Rationale: today's `ci-failure` workflow direct-commits to the PR
branch via `codex-apply-fix/`, the user has the branch-protection quality gate
plus the Codex App's PR review as safety nets, and switching to "open a fix PR"
introduces a new PR-management burden (closing, merging, syncing) for a path
that fires only on CI failure. The OpenAI cookbook's PR-open pattern is the
default for *external* consumers who lack our gate infrastructure; we have
that infrastructure.

### 5.5 `tag-respond` → RETIRE (verb router collapses)

**Reviewer CONCERN #6 resolved:** `check-auth/` retires alongside `tag-claude/`,
`claude-command-router/`, and `claude-tag-respond.yml` — the Codex GitHub App
handles `@codex review` and `@codex address that feedback` natively (the disclosure
footer on PR #276 documents both). There is no remaining verb that justifies
the verb-router infrastructure.

**Files deleted:**

- `.github/workflows/claude-tag-respond.yml`
- `tag-claude/action.yml` (entire directory)
- `claude-command-router/action.yml` (entire directory, including `lib/parse.sh`)
- `check-auth/action.yml` (entire directory)
- `.github/workflows/test.yml` (the parse.sh corpus test)

**Reviewer NIT for verification:** spec author confirmed via Glob that
`tests/cases.json` exists at `claude-command-router/tests/cases.json` and will
be deleted as part of the `claude-command-router/` directory deletion. Run
`git ls-tree HEAD -- claude-command-router/tests/cases.json` to verify at PR
time.

**What we lose:** a `@codex fix` or `@codex explain` UX. If the user needs these
later, file them as fresh sub-issues; do **not** preserve the verb router on
spec. The Codex App's built-in feedback-addressing covers the most common
"act on my review" case.

## 6. `runtime/` Retirement Plan

Entire `runtime/` tree retires. No overlay images needed — the action runs on
vanilla `ubuntu-latest`; the App runs in OpenAI's cloud.

**Files/directories deleted:**

- `runtime/ci-manifest.yaml`, `runtime/ci-manifest.schema.json`
- `runtime/base/Dockerfile`
- `runtime/overlays/{review,fix,explain}/{Dockerfile,CLAUDE.md,expected.yaml}`
- `runtime/shared/CLAUDE-ci.md`
- `runtime/scripts/*` (9 scripts + `tests/expected-matcher-fixture/`)

**Reviewer NIT #11 resolution:** `runtime/scripts/tests/` contains durable
matcher-fixture guidance. Before deletion, extract any non-obvious test patterns
into a memory file or into a comment on the closing issue for sub-issue #9
(below). Per CLAUDE.md `# Document Files § Lifecycle`, this is the
extract-then-delete drill.

**Workflows deleted (six):**

- `.github/workflows/runtime-build.yml`
- `.github/workflows/runtime-check-private-freshness.yml`
- `.github/workflows/runtime-prune-pending.yml`
- `.github/workflows/runtime-rollback.yml`
- `.github/workflows/overlay-smoke.yml`
- `.github/workflows/marker-emission-aggregate.yml`

**GHCR images:** `ghcr.io/glitchwerks/claude-runtime-{base,review,fix,explain}`
deleted after the cutover lands and a **30-day grace window** passes (in case
any external consumer pinned digests directly). Manual GHCR UI operation.
**unverified:** no audit of external consumers' digest pins; the grace window
is a defensive default, not measured. **Sequencing:** sub-issue #M
(external-consumer audit) MUST complete before the 30-day grace window starts,
so digest-pinned consumers receive a full 30 days of notice from the
audit-completion date rather than from the v3 release date.

**Secrets retired:** `GH_PAT` (only used by `runtime-build.yml`).

**Reviewer BLOCKING #1 secondary resolution:** the legacy spec/plan files
(`docs/superpowers/specs/2026-04-21-ci-claude-runtime-design.md` and
`docs/superpowers/plans/2026-04-22-ci-claude-runtime.md`) **delete** after the
durable rationale ("why containerization was chosen, and why it's now
discarded") is captured as a decision-log entry on the closing PR for sub-issue
#9 below. Per CLAUDE.md `# Document Files § Lifecycle`.

## 7. Quality Gate Replacement

**Today (delete):**
- `pr-review/action.yml:L330–L412` posts `claude-pr-review/quality-gate`.
- `:L414–L518` synthesizes structured marker HTML comments.
- `:L520–L642` posts `claude-pr-review/quality-gate-shadow`.
- Severity regex in `pr-review/lib/severity-regex.sh`.

**Rev 2 design — three options, recommendation = option 2:**

| Option | Mechanism | Trade-off |
|---|---|---|
| 1 | Branch-protection requires `chatgpt-codex-connector[bot]` review state = `APPROVED` | Strict; `COMMENTED` reviews on P2-only findings would falsely block |
| **2 (recommended)** | Small `codex-gate.yml` reads the App's review state; posts `codex-pr-review/quality-gate = success` unless state is `CHANGES_REQUESTED` | Matches GitHub native required-reviewer semantics; permissive on `COMMENTED` |
| 3 | Parse P0/P1 badge presence in review body | Returns to the regex problem #271 was escaping; NOT recommended |

**Option 2 design (`codex-gate.yml`):**

```yaml
on:
  pull_request_review:
    types: [submitted, edited, dismissed]

permissions:
  statuses: write
  pull-requests: read

jobs:
  gate:
    if: github.event.review.user.login == 'chatgpt-codex-connector[bot]'
    runs-on: ubuntu-latest
    steps:
      - name: Fail if head SHA was empty
        if: github.event.pull_request.head.sha == ''
        run: |
          echo "::error::pull_request.head.sha was empty (possible webhook payload issue or unusual event type). Gate cannot post commit status. Check the PR event payload or re-trigger the review."
          exit 1

      - name: Post quality-gate status
        # defensive: prior step already fails on empty SHA, but this guards
        # against step-skipping due to manual workflow_dispatch or unusual event shape
        if: github.event.pull_request.head.sha != ''
        env:
          GH_TOKEN: ${{ github.token }}
          REVIEW_STATE: ${{ github.event.review.state }}
          BOT_LOGIN: ${{ github.event.review.user.login }}
          HEAD_SHA: ${{ github.event.pull_request.head.sha }}
        run: |
          if [ "$REVIEW_STATE" = "changes_requested" ]; then
            CONCLUSION=failure
            DESCRIPTION="Codex requested changes — see the bot review for details"
          else
            CONCLUSION=success
            DESCRIPTION="Codex review state: $REVIEW_STATE"
          fi
          gh api repos/${{ github.repository }}/statuses/$HEAD_SHA \
            -f context='codex-pr-review/quality-gate' \
            -f state="$CONCLUSION" \
            -f description="$DESCRIPTION"
```

The bot-login filter (`github.event.review.user.login == 'chatgpt-codex-connector[bot]'`)
on the `gate` job's `if:` condition addresses Reviewer BLOCKING #1 / CONCERN #5:
only Codex's reviews trip the gate, not arbitrary reviewers. Human approvers can
still `APPROVE` / `REQUEST CHANGES` in parallel — those route through branch
protection's normal required-reviewer config, not this status check.

**Permissions** are declared at the **workflow level** (`permissions: { statuses:
write, pull-requests: read }` at the top of the file, not inside the job) per the
key convention in CLAUDE.md — GitHub ignores job-level permissions when calling
reusable workflows, and consistent top-level placement makes the grant surface
auditable at a glance.

**Branch-protection ruleset rename** (in lockstep with cutover): required check
`claude-pr-review/quality-gate` → `codex-pr-review/quality-gate`. Both names
required during the shadow-mode phase (§ 8); old name dropped only after the
go decision is made.

## 8. Shadow Mode (NEW — addresses BLOCKING #3)

**Duration:** ≥7 days AND ≥7 real (non-synthetic) PRs observed, with a maximum window of 14 days.

- **Minimum:** 7 days + 7 PRs — both must be met before the decision gate opens.
- **Maximum:** 14 days — if the PR count is still below 7 at day 14, the cutover proceeds on time alone with an explicit caveat recorded on the decision-gate sub-issue noting the limited sample size.
- **Aspirational:** 30 PRs if organically achieved within the window; additional data strengthens the decision but is not a blocking requirement.

**Setup:**

1. Codex GitHub App is enabled with Automatic reviews ON for `glitchwerks/github-actions`.
2. `claude-pr-review.yml` (Claude) continues to run unchanged.
3. `codex-gate.yml` posts `codex-pr-review/quality-gate`.
4. Branch protection requires **both** `claude-pr-review/quality-gate` (Claude
   path) and `codex-pr-review/quality-gate` (Codex path) during the window.
   PRs cannot merge unless both pass.
5. The user manually compares Codex's and Claude's reviews on every PR that
   merges during the window.

**Observation methodology.** During shadow mode, log observations on sub-issue
#N in a table with at minimum these columns: `PR#` | `Claude finding count
(by severity)` | `Codex finding count (by severity)` | `Findings unique to
each` | `False-positive count (each side)` | `Codex latency (trigger →
review-posted)`. The kill criteria (below) reference these columns directly —
without structured logging, the criteria are unverifiable at decision-gate time.

**Kill criteria (written, must be in spec):**

**Stay on Codex (cutover proceeds)** if and only if:
- False-positive rate ≤ Claude's observed rate during the same window
  (false-positive = a Codex finding the user judges incorrect or out-of-scope), AND
- No genuinely-blocking issue Claude flagged was missed by Codex within the
  window, AND
- Review latency ≤ 30 min on ≥80% of PRs.

**Revert to Claude (and reconsider the architecture)** if any of:
- Codex misses any genuinely-blocking issue Claude flagged.
- Codex false-positive rate > 2× Claude's observed rate.
- Review latency > 30 min on >20% of PRs.

**Decision gate:** at the end of the window, the user makes an explicit go/no-go
call. The spec **records the criteria**; it does not pre-judge the outcome.

**Failure mode if no-go:** because shadow mode preserves both gates and both
workflows, reverting is zero-cost — disable the Codex App in cloud config,
drop `codex-pr-review/quality-gate` from branch protection, and revisit the
architecture. The OAuth deadline (~2026-06-20) compresses this window — if
shadow mode starts ≤2026-05-27 it completes by ≤2026-06-03, leaving 2+ weeks
of buffer.

## 9. Migration Sequencing

| Order | Sub-issue | Why this order |
|---|---|---|
| 1 | #A (App + `AGENTS.md`) | No code change; observable side-by-side with Claude |
| 2 | #B (`codex-gate.yml`) | Provides replacement signal before removing old one |
| 3 | #C (branch protection — add new) | Both names required during transition |
| 4 | **SHADOW MODE WINDOW (§ 8)** | Both gates required; ≥7 days + ≥7 PRs (14-day max) |
| 5 | **DECISION GATE** (go/no-go) | Explicit user call; requires #O resolved (synchronize-event behavior confirmed) |
| 6 | #D, #E, #F (write-side migrations) — parallel | apply-fix, lint-failure, ci-failure |
| 7 | #G (retire verb router) | Last workflow migration |
| 8 | #H (drop `claude-pr-review/quality-gate` requirement) | After every Claude workflow gone |
| 9 | #I (delete `runtime/` tree + six workflows) | After every consumer of overlay images migrated |
| 10 | #J (docs: CLAUDE.md, README.md, examples) | Stabilize before tagging |
| 11 | #K (cut `v3.0.0`) | Cutover complete |
| 12 | #L, #M (GHCR image deletion +30d, external-consumer audit) | Post-release cleanup. **Note:** the 30-day grace window does NOT start at v3 release; it starts when #M completes. This guarantees digest-pinned consumers receive a full 30 days of notice from audit-completion regardless of when #M finishes. |

**Atomicity note — #G (retire verb router).** Sub-issue #G's PR must delete
`claude-tag-respond.yml`, `tag-claude/`, `claude-command-router/`, and
`check-auth/` in a single PR — not piecemeal. The four files form an
interconnected verb-router; partial deletion creates a partially-routed surface
that exists until the final piece lands.

**Hard deadline:** Anthropic OAuth EOL ~2026-06-20. Shadow mode must start by
~2026-05-27 to keep the window inside the deadline with buffer.

**Rollback path:** every migrated workflow lands on its own PR. If a Codex
workflow misbehaves between merge and OAuth EOL, revert the single PR — the
Claude-era workflow file returns and `CLAUDE_CODE_OAUTH_TOKEN` still works
until EOL. After EOL there is no rollback; the Claude path is dead substrate.

## 10. Naming / Versioning / Consumer-Facing

**Major version bump to `v3`.** Breaking changes for external consumers:
- `claude-*.yml` workflow filenames → `codex-*.yml` (where retained).
- `apply-fix/`, `lint-failure/` composite-action paths → `codex-apply-fix/`,
  `codex-lint-failure/`.
- `pr-review/`, `tag-claude/`, `claude-command-router/`, `check-auth/` paths
  → **deleted** (no replacement at that path).
- Required secret `CLAUDE_CODE_OAUTH_TOKEN` → `OPENAI_API_KEY` (for write-side
  workflows) + cloud-side App install (for review).
- `claude-pr-review/quality-gate` status name → `codex-pr-review/quality-gate`.

Keep `v2` floating tag frozen at the last Claude-era commit so existing
consumers don't surprise-upgrade. `v3` is the Codex line.

**Workflow naming convention:** `codex-*.yml` (symmetric with today's
`claude-*.yml`). Discussed alternatives (`ai-*.yml`, prefix-less) rejected as
either vague at consumer site or collision-prone with retained legacy names.

**Reviewer BLOCKING #4 — consumer onboarding files:**

- **`examples/` directory and `docs/consumer-onboarding.md`:** Both exist on
  main. `examples/` contains 5 caller-workflow templates plus a README
  (`examples/{README.md,claude-apply-fix.yml,claude-ci-failure.yml,claude-lint-failure.yml,claude-pr-review.yml,claude-tag-respond.yml}`).
  `docs/consumer-onboarding.md` also exists. Both reference
  `CLAUDE_CODE_OAUTH_TOKEN`, GHCR overlay packages, and `claude-*.yml@v2`
  `uses:` lines — all of which become invalid post-v3. They are added to
  `touches:` and to sub-issue #J's scope explicitly. (The planner's original
  Glob verification was a false negative; corrected 2026-05-20 by project-reviewer.)
  Verified via `git ls-tree -r origin/main` on 2026-05-20: returned
  `examples/{README.md,claude-apply-fix.yml,claude-ci-failure.yml,claude-lint-failure.yml,claude-pr-review.yml,claude-tag-respond.yml}`
  and `docs/consumer-onboarding.md`.
- **`README.md`:** verified via Grep to contain `CLAUDE_CODE_OAUTH_TOKEN`,
  `ghcr.io/glitchwerks/claude-runtime-*` digest pins, and `claude-*.yml@v2`
  `uses:` examples. **Full rewrite required** as part of sub-issue #J.

## 11. Proposed Sub-Issues (file under milestone `codex-pivot`)

The spec author proposes the breakdown below. Identifiers are letters (not
numbers) to avoid clashing with existing GitHub issue numbers — the router /
ops agent will assign actual issue numbers when filing.

- **#A — Stand up Codex GitHub App + initial `AGENTS.md`.** Cloud-side App
  install, configure auto-review, write top-level `AGENTS.md` translating the
  inline prompt from `pr-review/action.yml`. Verify on a throwaway PR.
  **Acceptance:** AGENTS.md is verified adequate by triggering Codex review on
  a throwaway test PR that contains at least one defect of a class the existing
  Claude `pr-review` prompt's domain-specific guidance was designed to catch
  (e.g. an unquoted shell variable expansion in a composite action's bash step,
  or a missing `packages: read` on a container-pinned workflow). If Codex's
  review surfaces that finding, AGENTS.md is adequate. If not, iterate on the
  AGENTS.md content and re-test before merging.
- **#B — Build `codex-gate.yml`.** Posts `codex-pr-review/quality-gate` based
  on Codex App review state. Filter to bot login per § 7. Depends on #A.
- **#C — Branch-protection ruleset update (transition).** Add
  `codex-pr-review/quality-gate` as required alongside the existing
  `claude-pr-review/quality-gate`. Both required during shadow mode.
- **#D — Migrate `apply-fix` → `codex-apply-fix`.** Rename composite action +
  workflow; contract preserved per § 5.2. Delete legacy `apply-fix.yml`.
- **#E — Migrate `lint-failure` → `codex-lint-failure`.** Rename, swap agent,
  unify with `lint-fix` two-job legacy. Delete `lint-diagnose/`, `lint-apply/`,
  `claude-lint-fix.yml`. Apply the `/tmp/` → `${{ github.workspace }}/.tmp/`
  workspace-sandbox fix from § 5.3.
- **#F — Migrate `ci-failure` → `codex-ci-failure`.** Direct-commit semantics
  retained per § 5.4 (NIT #10 resolution). Delete legacy `ci-failure.yaml`.
- **#G — Retire `@claude` verb router.** Delete `claude-command-router/`,
  `tag-claude/`, `check-auth/`, `claude-tag-respond.yml`, `test.yml`.
- **#H — Drop `claude-pr-review/quality-gate` branch-protection requirement.**
  Final cutover step after all Claude workflows removed.
- **#I — Delete `runtime/` tree.** All files in § 6, all six runtime workflows.
  Extract durable matcher-test guidance and runtime decision-log per § 6 first.
- **#J — Rewrite consumer examples + onboarding for v3.** Rewrite
  `examples/{README.md,claude-apply-fix.yml,claude-ci-failure.yml,claude-lint-failure.yml,claude-pr-review.yml,claude-tag-respond.yml}`
  and `docs/consumer-onboarding.md` to remove `CLAUDE_CODE_OAUTH_TOKEN`
  references, GHCR overlay package install steps, and `claude-*.yml@v2`
  `uses:` lines. Replace with the post-cutover surface (`codex-*.yml@v3`,
  `OPENAI_API_KEY` secret, and the App-handled PR-review path which requires
  no caller-workflow file). Also update `CLAUDE.md` and `README.md`
  (architecture rewrite, secrets table refresh) and retire legacy runtime
  spec + plan files per CLAUDE.md lifecycle rule (durable content extracted
  first). Acceptance: a fresh consumer following the rewritten
  examples/onboarding can complete setup against
  `glitchwerks/github-actions@v3` without any reference to retired surfaces.
  **Test method:** Use a throwaway repo (e.g., `cbeaulieu-gt/codex-pivot-consumer-test`
  or a fresh personal repo) as the consumer test bed. The acceptance is met
  when a clean checkout of that test repo, following only the rewritten
  `examples/README.md` and `docs/consumer-onboarding.md`, can install the
  Codex GitHub App, open a test PR, and observe a Codex review post — with
  no reference to retired Claude/GHCR/OAuth surfaces in the consumer's
  workflow.
  **Gating sub-issue — must merge before `v3` tag is cut.**
- **#K — Cut `v3.0.0` release.** Move `v3` floating tag, freeze `v2` at last
  Claude-era commit, write release notes documenting all breaking changes
  from § 10.
- **#L — (Post-cutover, +30 days) Delete GHCR images.** Manual GHCR UI on
  `claude-runtime-{base,review,fix,explain}`.
- **#M — Audit external consumers pinned to `v2`.** Survey before `v3`
  release; notify of breaking-change nature.
- **#N — Document shadow-mode kill-criteria observations.** A short results
  log (PR count, false-positive comparison, latency, decision) extracted from
  shadow mode and attached to whichever sub-issue closes the decision gate.
- **#O — Verify Codex App `synchronize`-event behavior before retiring
  `claude-pr-review.yml`.** The current Claude pr-review handles `synchronize`
  events by reviewing only new commits (`git diff before..after`). Codex's
  documented triggers are PR open, draft→ready, and `@codex review` comment —
  `synchronize` is not explicitly listed. Before the cutover decision-gate in
  §9, run a controlled test: open a PR with the Codex App enabled, push a
  follow-up commit, observe whether the App posts a fresh review automatically.
  **Outcomes and fallbacks:**
  - **App auto-reviews on `synchronize`:** no action needed; Claude can be
    retired on schedule.
  - **App does NOT auto-review on `synchronize`:** the cutover plan must add
    either (a) a small `codex-synchronize-trigger.yml` workflow that posts
    `@codex review` on synchronize events, or (b) accept reduced review
    coverage on push-after-open and document it in `examples/README.md`.
  **Gating:** this sub-issue MUST resolve before the §9 decision gate. Do NOT
  delete `claude-pr-review.yml` without an answer.

  **Timing:** Run this test as part of sub-issue #A (App setup) or #B
  (`codex-gate.yml`), before the shadow mode window begins. This ensures any
  fallback workflow (#O option (a) `codex-synchronize-trigger.yml`) can be
  built in parallel with shadow-mode setup without delaying the decision gate.

## 12. Out of Scope

- **`lint.yml` (actionlint)** — unaffected.
- **`verify-app-secrets.yml`** — keep; App secrets are still in use for write-side workflows.
- **Local dev loop** — Claude Code on the user's machine is unchanged.
- **Codex memory / persona files beyond `AGENTS.md`** — `AGENTS.md` is the only
  mechanism Codex respects ([source](https://developers.openai.com/codex/integrations/github), fetched 2026-05-20).
  Deletion of `runtime/shared/CLAUDE-ci.md` is permanent.
- **`@codex fix` / `@codex explain` verbs** — out of scope. If the user wants
  these later, file fresh issues; do not preserve the verb router on spec.

## 13. Open Questions for the User (gating sub-issue filing)

These are questions Rev 2 cannot answer in writing. The user should resolve
before #A is filed.

1. **Shadow-mode window length (resolved 2026-05-20 by reviewer feedback).**
   Binding floor: ≥7 days AND ≥7 real PRs. Maximum: 14 days (cutover proceeds
   on time even if <7 PRs, with caveat). ≥30 PRs is aspirational. See §8.
2. **Severity threshold for `CHANGES_REQUESTED`.** Spike #275 observed
   `COMMENTED` on a P2 finding; the spec recommends gating on `!= CHANGES_REQUESTED`
   (option 2 in § 7). Confirm this matches the user's risk tolerance — if a P1
   finding emits `COMMENTED` (undocumented behavior), option 2 would let it
   merge.
3. **External consumer audit timing.** Sub-issue #M is listed post-release in
   § 9. Should it run **before** the `v3` cut instead, to give consumers a
   migration window?
4. **`AGENTS.md` voice and detail.** The PR-review prompt at
   `pr-review/action.yml:L1–L696` is verbose and Claude-specific. How much
   of it translates verbatim vs. gets rewritten for Codex's conventions? (The
   App's docs note Codex follows "Review guidelines" sections specifically.)
5. **`OPENAI_API_KEY` budget cap.** Recommend setting a hard cap (OpenAI's
   billing dashboard supports this) so a runaway workflow can't burn through
   the user's account. Acceptable cap value?

## 14. Definition of Done

- All five Claude-Code-Action workflows replaced (4) or retired (1) per § 5.
- `runtime/` tree fully deleted; GHCR images scheduled for deletion (+30d).
- `CLAUDE_CODE_OAUTH_TOKEN` removed from repo secrets.
- `OPENAI_API_KEY` added; identity model documented in `CLAUDE.md`.
- `AGENTS.md` exists at repo root with review guidelines.
- `codex-pr-review/quality-gate` is the **sole** required PR-review check on
  branch protection; `claude-pr-review/quality-gate` removed.
- `codex-gate.yml` posts the new status filtered to the Codex bot login.
- `v3.0.0` tag cut, `v3` floating tag moved, `v2` frozen at last Claude-era
  commit, release notes published.
- `CLAUDE.md` Architecture + Required Secrets sections accurate; `README.md`
  consumer examples accurate.
- Legacy runtime spec + plan files deleted per CLAUDE.md doc lifecycle rule
  (durable content extracted to memory or decision log first).
- Shadow-mode results documented (sub-issue #N).

---

## Sources

- [openai/codex-action README](https://github.com/openai/codex-action) (fetched 2026-05-20) — action inputs, outputs, auth model, sandbox, safety-strategy, `@v1` floating tag
- [Codex GitHub Action docs](https://developers.openai.com/codex/github-action) (fetched 2026-05-20) — required permissions, OS support, posting reviews via `actions/github-script`
- [Codex GitHub integration (App)](https://developers.openai.com/codex/integrations/github) (fetched 2026-05-20) — App installation, `@codex review`, automatic reviews, P0/P1 filtering, `AGENTS.md` customization
- [Codex pricing](https://developers.openai.com/codex/pricing) (fetched 2026-05-20) — subscription coverage, API-key billing
- [Codex CLI autofix cookbook](https://developers.openai.com/cookbook/examples/codex/autofix-github-actions) (fetched 2026-05-20) — `workflow_run`-triggered autofix pattern
- [Spike #275 closing comment](https://github.com/glitchwerks/github-actions/issues/275) (fetched 2026-05-20) — bot identity, subscription tier, context-aware reading, trigger list, severity-badge format, review-state semantics, depth-mode timing
- [PR #276](https://github.com/glitchwerks/github-actions/pull/276) (fetched 2026-05-20) — real `chatgpt-codex-connector[bot]` review evidence, `author_association: NONE`, `state: COMMENTED` on P2 finding
- `docs/superpowers/research/2026-05-20-codex-evaluation.md` (PR #277, pending merge as of spec write) — Phase 0 descriptive research; spec retains only load-bearing facts
- Repo internals: `pr-review/action.yml:L1–L696`, `apply-fix/action.yml:L1–L93`, `claude-command-router/action.yml:L1–L98`, `check-auth/action.yml:L1–L62`, `runtime/` tree, `CLAUDE.md § Architecture`, `CLAUDE.md § CI Runtime (Phase 1+)`, `CLAUDE.md § Required secrets`, `README.md` (Grep-verified 2026-05-20 to contain Claude-era token + image references)
- Epic #273; quality-gate context #271, #270; ruleset enforcement #176; container `packages: read` discovery #192; git safe.directory baking #199; spike #275; spike PR #276
