# Runtime Overlay Recovery Plan

**Status: DRAFT — pending review**

| Field | Value |
|---|---|
| Created | 2026-05-08 |
| Issues | [#242](https://github.com/glitchwerks/github-actions/issues/242), [#245](https://github.com/glitchwerks/github-actions/issues/245) |
| Closes | #245 via W1+W2; #242 via W3 |
| Related | glitchwerks/siege-web#304, glitchwerks/siege-web#308, glitchwerks/siege-web#309 |

---

## Context

### Architectural finding

The runtime overlay design bakes agents, skills, plugins, and hooks at `/opt/claude/.claude/` inside each verb-specific container image. The design intent is that the CLI, when invoked by `claude-code-action@v1`, discovers that content and makes it available for invocation. That intent does not hold in practice.

Three independent sources — the GHA runner `docker create` log, the `claude-code-action@v1` source (`setup-claude-code-settings.ts`), and the live run log from siege-web [run 25567112823](https://github.com/glitchwerks/siege-web/actions/runs/25567112823) — establish the same fact: **GitHub Actions unconditionally injects `-e HOME=/github/home` at container startup**, overriding the image's `ENV HOME=/opt/claude`. Every component of `claude-code-action@v1` that touches the filesystem — binary installation, settings-path resolution, `settingSources` — derives its paths from `os.homedir()` at call time, which reads the overridden `HOME`. The CLI's `"user"` settings source therefore resolves to `/github/home/.claude/`, a directory created fresh by the action's own setup step. It contains only a generated `settings.json`. The baked tree at `/opt/claude/.claude/` is never consulted. (Full proof: [#245 comment](https://github.com/glitchwerks/github-actions/issues/245#issuecomment-4408160311).)

A secondary delivery failure compounds this: the `--allowedTools` list passed to `claude-code-action@v1` in `pr-review/action.yml` is scoped to `Bash(gh pr diff:*)`, `Bash(gh pr review:*)`, and `Bash(gh pr view:*)`. It does not include `Task` or `Skill`. Even if baked agents and skills were on the discovery path, the LLM could not invoke them — they would not be in the allowed-tools surface.

The `APPEND_SYSTEM_PROMPT` mechanism (Option A, tested via siege-web PR #309) and the `$HOME/.claude/CLAUDE.md` copy approach (Option B, shipped as v2.4.2 in PR #243) both improve persona delivery, but neither restores the baked agent/skill surface.

The `marker_missing` failure (#242) is a direct consequence: the persona's strict-format output contract (the `<!-- claude-pr-review-summary-v1` HTML-comment block) is appended as a prompt instruction, not enforced with authority, and the LLM's compliance is inconsistent. The structured-marker shadow gate introduced in #185 Phase 2 has therefore never moved off `marker_missing`.

### What this is NOT

The recovery is a delivery fix, not a redesign. The runtime overlay design's intent — verb-scoped agent surfaces, the "different eyes" guarantee, the `expected.yaml` inventory contract — remains sound. Filesystem isolation is real and load-bearing. The three workstreams below repair the delivery gap; they do not revisit the architecture.

---

## W1 — Bridge baked content into CLI discovery path

### Problem

`/opt/claude/.claude/{agents,skills,plugins,hooks,commands}/` is never on the CLI's discovery path because `HOME` is overridden at container start. The bridge copies that content into `$HOME/.claude/` before the action's setup step writes `settings.json`, so the CLI's `"user"` settings source sees the baked surface.

### Deliverable

A shell step, added immediately after `Install persona for claude-code-action CLI` in each action and workflow that invokes `claude-code-action@v1`:

```yaml
- name: Bridge baked overlay content into CLI discovery path
  shell: bash
  run: |
    BAKED_DIR=/opt/claude/.claude
    TARGET_DIR="$HOME/.claude"
    mkdir -p "$TARGET_DIR"
    for subdir in agents skills plugins hooks commands; do
      if [ -d "$BAKED_DIR/$subdir" ]; then
        # --no-clobber: don't overwrite the settings.json or CLAUDE.md
        # already written by the Install persona step.
        cp -r --no-clobber "$BAKED_DIR/$subdir" "$TARGET_DIR/"
        echo "Bridged: $subdir"
      fi
    done
```

**Files to update:**

| File | Step insertion point |
|---|---|
| `pr-review/action.yml` | After `Install persona for claude-code-action CLI` |
| `lint-failure/action.yml` | After the equivalent persona-install step (or at step start if absent) |
| `lint-diagnose/action.yml` | Same |
| `tag-claude/action.yml` | Same |
| `.github/workflows/claude-ci-failure.yml` | Before the `claude-code-action@v1` step |
| `.github/workflows/claude-tag-respond.yml` | Before the `claude-code-action@v1` step in the `dispatch` job |

The `--no-clobber` flag is critical: `pr-review/action.yml` already writes `$HOME/.claude/CLAUDE.md` via the `Install persona` step and `$HOME/.claude/settings.json` is written by the action's own setup. Neither must be overwritten.

### Acceptance criteria

- A review run's log shows `Bridged: agents`, `Bridged: skills`, `Bridged: plugins`.
- The CLI's startup output (visible via `ACTIONS_STEP_DEBUG=true`) lists at least one agent from `runtime/overlays/review/expected.yaml` in the available-tools / registered-agents enumeration.
- `cp -r --no-clobber` leaves `$HOME/.claude/CLAUDE.md` (written by the prior persona-install step) unchanged.

---

## W2 — Expand `--allowedTools` per overlay

### Problem

The `--allowedTools` string in `pr-review/action.yml` restricts Claude to three `Bash` patterns:

```
Bash(gh pr diff:*),Bash(gh pr review:*),Bash(gh pr view:*)
```

`Task` and `Skill` are absent. Even after W1 bridges the baked agent surface into the discovery path, the LLM cannot invoke those agents. The tool-allowlist is the last delivery barrier.

### Deliverable

Per-overlay `--allowedTools` expansion. The review composite already has a narrow Bash scope that is correct for its read-only posture; we extend it rather than replace it.

**`pr-review/action.yml` (review overlay):**

```
--allowedTools "Task,Skill,Bash(gh pr diff:*),Bash(gh pr review:*),Bash(gh pr view:*),Bash(gh api:*)"
```

Rationale: `Task` enables sub-agent dispatch to `inquisitor` and the `pr-review-toolkit` agents; `Skill` enables skill invocation; `Bash(gh api:*)` is needed by the persona's sub-agents for targeted API calls. The review overlay's `must_not_contain` in `expected.yaml` enforces that write-side agents (`code-writer`, `apply-fix`-adjacent) are not on disk — filesystem isolation remains the "different eyes" enforcement layer.

**`tag-claude/action.yml` and `claude-tag-respond.yml` (fix + explain overlays):**

Fix overlay additionally needs:

```
Task,Skill,Bash(git:*),Bash(gh pr:*),Bash(gh api:*),Bash(.../git-push.sh:*)
```

Explain overlay is read-only (same scope as review, no commit/push Bash patterns):

```
Task,Skill,Bash(gh pr diff:*),Bash(gh pr view:*),Bash(gh api:*)
```

These are initial scopes; the implementation PR should verify each against the relevant `expected.yaml` to confirm the agent set's actual tool needs.

**CI-failure and lint-failure composites:**

These use the fix overlay. Apply the fix-overlay allowlist above.

### Acceptance criteria

- A review run's `ALLOWED_TOOLS` log line (emitted by `claude-code-action@v1`) includes `Task` and `Skill`.
- The review does not regress: the read-only Bash patterns remain present; no write-side Bash patterns (`git commit`, `git push`, `git apply`) appear in the review overlay's expanded list.
- `expected.yaml`'s `must_not_contain` check continues to pass in `runtime-build.yml` — confirming filesystem isolation is enforced at build time alongside the allowlist enforcement at run time.

---

## W3 — Marker synthesis via post-processing (closes #242)

### Problem

The structured-marker output contract (the `<!-- claude-pr-review-summary-v1` HTML-comment block) is specified in the review overlay's CLAUDE.md as a required LLM output. The LLM's compliance is inconsistent: the shadow gate has reported `marker_missing` on every run since #185 Phase 2 shipped (#242). The `APPEND_SYSTEM_PROMPT` position means the instruction is appended rather than authoritative, and LLM turn-budget pressure can truncate the response before the marker is emitted.

The fix is to stop relying on the LLM to emit the marker and instead synthesize it deterministically in a post-processing step that runs after `claude-code-action@v1`.

### Deliverable

A post-processing step in `pr-review/action.yml`, inserted after the `Quality gate — post claude-pr-review/quality-gate status` step and before the `Quality gate — structured marker (advisory shadow)` step:

```yaml
- name: Synthesize structured marker via post-processing
  if: steps.authz.outputs.skip != 'true' && steps.size-check.outputs.skip != 'true' && steps.claude-review.outcome == 'success'
  shell: bash
  env:
    GH_TOKEN: ${{ github.token }}
    GH_REPOSITORY: ${{ github.repository }}
    PR_NUMBER: ${{ github.event.pull_request.number }}
  run: |
    set -euo pipefail
    REPO="$GH_REPOSITORY"

    # Fetch latest bot comment (same fetch pattern as quality-gate step)
    BODY=$(gh api "repos/$REPO/issues/$PR_NUMBER/comments?per_page=100" \
      --jq 'map(select(.user.login == "github-actions[bot]")) | sort_by(.updated_at) | last | .body // ""' \
      2>/dev/null || echo "")

    [ -z "$BODY" ] && { echo "No bot comment — skipping marker synthesis"; exit 0; }

    # Skip if marker already present (LLM happened to emit it correctly)
    if printf '%s' "$BODY" | grep -qF '<!-- claude-pr-review-summary-v1'; then
      echo "Marker already present in review body — no synthesis needed"
      exit 0
    fi

    # Count severity markers using the same regex as the authoritative gate
    CRITICAL=$(printf '%s' "$BODY" | grep -cE '🔴 Critical|Critical \(BLOCKING\)|\*\*BLOCKING\*\*' || true)
    HIGH=$(printf '%s' "$BODY"     | grep -cE '🟡 High-Priority|\*\*MAJOR\*\*' || true)
    MEDIUM=$(printf '%s' "$BODY"   | grep -cE '🟢 Medium' || true)
    LOW=$(printf '%s' "$BODY"      | grep -cE '\bNit\b' || true)

    MARKER=$(printf '<!-- claude-pr-review-summary-v1\n{"schemaVersion":1,"findings":{"critical":%d,"high":%d,"medium":%d,"low":%d}}\n-->' \
      "$CRITICAL" "$HIGH" "$MEDIUM" "$LOW")

    # Fetch the comment ID to PATCH
    COMMENT_ID=$(gh api "repos/$REPO/issues/$PR_NUMBER/comments?per_page=100" \
      --jq 'map(select(.user.login == "github-actions[bot]")) | sort_by(.updated_at) | last | .id' \
      2>/dev/null || echo "")

    if [ -z "$COMMENT_ID" ]; then
      echo "::warning::Could not resolve comment ID for marker append"
      exit 0
    fi

    NEW_BODY=$(printf '%s\n\n%s' "$BODY" "$MARKER")

    gh api "repos/$REPO/issues/comments/$COMMENT_ID" \
      -X PATCH \
      -f body="$NEW_BODY"
    echo "Marker synthesized and appended: critical=$CRITICAL high=$HIGH medium=$MEDIUM low=$LOW"
```

**Parser alignment.** The severity-counting regexes in the post-processor and in the authoritative quality-gate step (`Quality gate — post claude-pr-review/quality-gate status`) must agree exactly. The implementation PR should extract the shared regex into a sourced shell fragment (e.g., `pr-review/lib/severity-regex.sh`) used by both steps, so future regex changes cannot desync them.

**`parse-marker.sh` compatibility.** The synthesized marker has the same format as an LLM-emitted marker. `parse-marker.sh` does not need changes — the shadow gate step reads whatever is in the comment body, LLM-authored or synthesized.

### Acceptance criteria

- The shadow gate's `MARKER_OUTCOME` transitions from `marker_missing` to `clean` or `blocking` (whichever is correct for the review's severity content).
- The synthesized marker's `findings.*` counts match the severity-marker counts in the review body prose — verified by inspection on a run with at least one finding of each severity level.
- When the LLM does emit the marker correctly, the `grep -qF` guard skips re-synthesis.
- The authoritative gate (`claude-pr-review/quality-gate`) and the shadow gate (`claude-pr-review/quality-gate-shadow`) agree (same `findings.critical + findings.high > 0` result) for the same review body.

---

## Sequencing and dependencies

```
W1 ──┐
     ├── single PR (#246 or similar) ── merge ── verify in siege-web
W2 ──┘

W3 ── independent PR ── verify in siege-web
```

W1 and W2 address the same delivery gap (baked content not reaching the CLI) and should ship together in a single PR. They have no dependency on W3.

W3 addresses the marker-synthesis problem independently. It can be authored in parallel with W1+W2 and merged in either order, though merging W1+W2 first is preferred so the verification baseline (W3 verification) includes the corrected agent surface.

**All three workstreams must be verified against siege-web pre-merge** using the floating-tag or branch-ref verification pattern (see Verification Strategy below) before the v2.4.3 release tag is cut.

---

## Verification strategy

### Pattern: floating-tag or branch-ref in siege-web

The standard pre-merge verification pattern for this repo:

1. On the implementation branch (e.g., `issue-245-recovery`), move the floating `v2` tag to point at the branch's HEAD, OR configure siege-web's caller workflow to reference the branch directly (`glitchwerks/github-actions/.github/workflows/claude-pr-review.yml@issue-245-recovery`).
2. Open or push a PR in siege-web that will trigger `claude-pr-review`.
3. Inspect the Actions run log for the smoking-gun lines below.
4. Restore `v2` to `main` HEAD after verification.

**Caution — the `pull_request_target` resolution trap:** `pull_request_target` resolves the called workflow from the **base branch** of the triggering PR, not the head branch. This means a siege-web verification PR opened against `main` will resolve the reusable workflow at `main` regardless of the head branch's workflow file. To test a pre-merge composite, either (a) use the floating-tag approach above, or (b) use a siege-web branch whose base is also a branch pointing at the test composite. Do not push a siege-web PR against `main` and expect it to pick up the unreleased composite changes — it won't. This trap caused the failed Option A verification in glitchwerks/siege-web#309.

### Per-workstream smoking-gun log lines

**W1 (bridge):**

With `ACTIONS_STEP_DEBUG=true` on the siege-web Actions run:

```
Bridged: agents
Bridged: skills
Bridged: plugins
```

Visible in the `Bridge baked overlay content into CLI discovery path` step log. Additionally, the Claude CLI startup section should enumerate `inquisitor` (or another agent from `expected.yaml`) in its registered-agents list.

**W2 (allowlist):**

In the `claude-code-action@v1` step log, the `ALLOWED_TOOLS` line emitted by `run.ts`:

```
ALLOWED_TOOLS: Task,Skill,Bash(gh pr diff:*),Bash(gh pr review:*),Bash(gh pr view:*),Bash(gh api:*)
```

**W3 (marker synthesis):**

In the `Synthesize structured marker via post-processing` step log:

```
Marker synthesized and appended: critical=N high=N medium=N low=N
```

And in the shadow gate step's summary table:

```
| Structured marker | `clean` |   (or `blocking` — either is success; `marker_missing` is failure)
```

The siege-web `claude-pr-review/quality-gate-shadow` commit status should show `success` (agree:clean or agree:blocking) rather than `error / marker_missing`.

---

## Existing artifact cleanup

| Artifact | Action | Rationale |
|---|---|---|
| PR #244 (`issue-242-option-a` branch) | Close in favor of W1+W2+W3 PRs | Contains Option A `APPEND_SYSTEM_PROMPT` + delimiter hardening; useful as reference but the approach is superseded. The verification-only commit (`1602470`) is not needed. If reusing the branch as W1+W2 foundation, rebase selectively. |
| glitchwerks/siege-web PR #309 | Close | Verification scaffolding for Option A; result was negative for marker delivery but informed the architectural finding in #245. Close with a reference to this plan. |
| glitchwerks/siege-web issue #308 | Close | Tracked the #309 verification run. Close once #309 is closed. |
| glitchwerks/siege-web issue #304 | Close | Tracked the v2.4.1 → v2.4.2 bump. The bump shipped but did not fix `marker_missing`; superseded by v2.4.3 once W1+W2+W3 land. |
| glitchwerks/siege-web PR #305 | Close | The v2.4.2 bump PR itself. Already merged; close the corresponding issue (#304) rather than the PR. |
| github-actions v2.4.2 release | Leave as-is | It is effectively a no-op release (persona-copy step only; baked content still orphaned) but is doing no harm. v2.4.3 will be the recovery release. |
| github-actions issue #242 | Leave open | Tracks `marker_missing` specifically. Closes when W3 lands and the shadow gate transitions off `error / marker_missing`. |
| github-actions issue #245 | Leave open | Closes when W1+W2 land (the "are baked agents reachable" question is answered by making them so). |

---

## Open questions and risks

### W1: file permissions on `cp -r` from `/opt/claude/.claude/`

The baked tree is owned by root (mode `0755` per the Dockerfile's `COPY --chown=root:root` convention). The container job runs as the GHA runner UID (non-root). `cp -r` from a root-owned source into a runner-writable `$HOME/.claude/` works as long as the source files are world-readable — which `0755`/`0644` directories and files are. Verify during W1 pre-merge testing that no `Permission denied` appears in the bridge step log. If permissions are tighter, a Dockerfile change to `chmod -R o+rX /opt/claude/.claude/` resolves it.

### W2: allowlist blast-radius and "different eyes" integrity

Expanding `--allowedTools` to include `Task` and `Skill` allows the LLM to dispatch sub-agents during a review run. The "different eyes" guarantee is now dual-layered: (1) filesystem isolation — write-side agents are not on disk, enforced by `expected.yaml` / `inventory-match.sh` at build time; (2) allowlist scoping — the Bash patterns in the review overlay's allowlist must not include write-side patterns (`git commit`, `git apply`, `git push`). Verify that `inventory-match.sh` runs in `runtime-build.yml` on both PR and push events before merging W2. A build-time regression that allows `code-writer` into the review image would not be caught by the allowlist alone.

### W3: severity regex agreement between post-processor and authoritative gate

The post-processor counts severity markers and synthesizes `findings.*` counts; the authoritative gate uses the same regex to produce its `BLOCKER_HITS` count. If the two regexes drift, the shadow gate's `agree:clean` / `agree:blocking` classification disagrees with the authoritative gate on the same review body — a silent quality-gate desync. Mitigation: extract the shared regex into `pr-review/lib/severity-regex.sh` (a sourced shell fragment), used by both the authoritative gate step and the post-processor step. Any future regex change touches one file and both consumers stay in sync.

### Hardening follow-up (post-recovery)

The root cause of #245 is that `runtime-build.yml`'s smoke tests verify the baked tree's structure but not whether the CLI actually discovers that content at runtime. A future smoke-test enhancement — a minimal `claude-code-action@v1`-shaped invocation (single-turn, no actual PR diff, `--print` mode) that emits the agent-registration log — would have caught the HOME-override problem at build time. This is out of scope for W1/W2/W3 but is the highest-value hardening action post-recovery.

---

## Out of scope

The following are explicitly excluded from this plan. They may be revisited as future work but are not required for the recovery.

- **Forking `claude-code-action@v1`**: not needed. W1 bridges the baked content via a pre-step; W2 expands the allowlist; neither requires modifying the upstream action.
- **Reclaiming CLI invocation entirely** (running `claude` directly rather than through `claude-code-action@v1`): technically possible and would give full control over `settingSources` and `--allowedTools`, but it is a much larger change and not required for the delivery fix.
- **The `bot/` and `wiki/` paths in siege-web**: unrelated to the overlay recovery.
- **Redesigning the overlay layer model**: the spec's §3.1 / §3.4 layer model is sound. This plan implements it correctly, not differently.
