# Phase 6 — Promotion automation, rollback, freshness alarm, prune

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automate digest promotion (single-PR atomic bump of all four `@sha256:<digest>` references), provide targeted rollback, daily orphan-tag pruning, and weekly staleness alarm for the pinned private ref — closing the operational loop opened by Phase 5's manual digest wiring.

**Architecture:** STAGE 5 of `runtime-build.yml` reads digest outputs from STAGE 2 + STAGE 3 and uses `peter-evans/create-pull-request` (SHA-pinned) to open one PR rewriting digest pins via `sed -E` regex substitution scoped per-overlay-name across 5 reusable workflows (7 occurrences). Three new standalone workflows under `runtime/` provide the safety net: `rollback.yml` (workflow_dispatch with `target_pubsha` input, mirrors STAGE 5's PR mechanism in reverse), `check-private-freshness.yml` (weekly cron, path-scoped denominator per §13 Q7, idempotent `gh issue create` by exact-title dedupe), and `prune-pending.yml` (daily cron deleting `pending-*` tags older than 30 days via GHCR REST, never touches `:<pubsha>` or `@sha256:` refs).

**Tech Stack:** GitHub Actions (`workflow_call`, `workflow_dispatch`, `schedule`), Bash + jq + yq + sed on `ubuntu-latest`, `peter-evans/create-pull-request@<SHA>`, `gh api` for GHCR REST, `actions/create-github-app-token@<SHA>` for App-token resolution, `actionlint` (existing `lint.yml` workflow).

**Master plan reference:** `docs/superpowers/plans/2026-04-22-ci-claude-runtime.md` §Phase 6 (lines 358–396).
**Spec sections:** §6.2 STAGE 5 (lines 359–370), §9.3 Rollback (631–651), §9.4 Prune (653–659), §11.3 Staleness alarm (792–803), §13 Q4/Q5/Q7 (lines 832, 833, 835).
**Issue:** #144.

---

## File structure

| Action | Path | Responsibility |
|---|---|---|
| Modify | `.github/workflows/runtime-build.yml` | Append `stage-5-promote` job — gated on STAGE 4 success + non-PR event |
| Create | `runtime/rollback.yml` | Targeted rollback to a prior `pubsha`; mirrors STAGE 5 in reverse |
| Create | `runtime/check-private-freshness.yml` | Weekly staleness alarm; path-scoped denominator |
| Create | `runtime/prune-pending.yml` | Daily orphan `pending-*` tag cleanup |
| Modify | `runtime/ci-manifest.yaml` | Add comment block near `sources.marketplace.ref` documenting manual-bump cadence (Q5) |
| Modify | `docs/superpowers/specs/2026-04-21-ci-claude-runtime-design.md` | §13 Q5 spec amendment closing the open question (Q4 tracked in PR body, no spec change needed) |
| Modify | `CLAUDE.md` | Add `Phase 6 status` paragraph to "CI Runtime" section |
| Modify | `README.md` | Add "Promotion + rollback" subsection to existing CI runtime section |

**Workflows under `runtime/` not `.github/workflows/`:** intentional — they are runtime-tooling workflows not consumer-facing reusable workflows. They live next to the manifest they serve. (Per master plan file structure block lines 64–66.)

---

## Pre-execution checks

These steps gather inputs the plan can't hard-code; run them before Task 6.1.

- [ ] **PE-1: Look up `peter-evans/create-pull-request` latest stable release SHA.**
  Use `mcp__plugin_context7_context7__query-docs` with library ID `/peter-evans/create-pull-request`, OR fetch the repo's releases page directly. Pin to the SHA of the latest stable release tag (e.g., `v7.0.5` → some `<40-hex>`). Record the SHA + the human-readable version as a comment alongside every `uses:` line that references this action. Never use a floating `@v7` ref.

- [ ] **PE-2: Look up `actions/create-github-app-token` latest stable release SHA.**
  Same procedure. Used in `rollback.yml` to mint an App token for opening the rollback PR. Record SHA + version.

- [ ] **PE-3: Confirm GHCR REST endpoints + scopes.**
  - List package versions: `GET /orgs/glitchwerks/packages/container/{package}/versions` — requires `read:packages`.
  - Delete a package version: `DELETE /orgs/glitchwerks/packages/container/{package}/versions/{version_id}` — requires `delete:packages` (or `packages: write` on the workflow's `GITHUB_TOKEN` for the same org).
  - The four package names: `claude-runtime-base`, `claude-runtime-review`, `claude-runtime-fix`, `claude-runtime-explain`.

- [ ] **PE-4: Confirm `peter-evans/create-pull-request` does NOT push the existing branch when `branch:` matches an existing remote branch.**
  Default behavior: it creates the branch if missing, force-pushes the new tree if existing. We want this — the digest-bump branch is named `auto/runtime-promote-<pubsha>` and is recreated per build. Validate the action's docs say so.

- [ ] **PE-6: Verify the existing GitHub App's installation covers `glitchwerks/claude-configs`.**
  Run `gh api /repos/glitchwerks/claude-configs/installation` (with a token that has read access). If it returns the same App ID as `APP_ID`, the App can authenticate to `claude-configs` and Task 6.5 uses it via `actions/create-github-app-token`. If it returns a different App ID (or 404), we need a separate auth path — STOP and surface to the user before proceeding with Task 6.5.

- [ ] **PE-7: Verify `peter-evans/create-pull-request` interprets `draft: 'true'`/`'false'` correctly at the pinned SHA from PE-1.**
  Run a `workflow_dispatch` test of `runtime-rollback.yml` against a throwaway branch, with `inputs.dry_run=true` and again with `inputs.dry_run=false`. Confirm the resulting PR's `draft` state matches the input. If `peter-evans/create-pull-request` accepts only literal `true`/`false` (not `'1'`/`'0'`), the normalization in Step 6.3.6b is sufficient. If it only accepts an unquoted boolean expression, change the `with: draft:` line to `${{ fromJSON(steps.mode.outputs.dry_run) }}`.

- [ ] **PE-5: Capture current digest references for sanity-check baseline.**
  Run from worktree root:
  ```bash
  grep -E "claude-runtime-(base|review|fix|explain)@sha256:[a-f0-9]{64}" .github/workflows/claude-*.yml
  ```
  Expected output: 7 lines (review×2, fix×4, explain×1, base×0 — base is not referenced by any reusable workflow; only overlays are pinned by the consumer surface). Save the output to `/tmp/baseline-digests.txt` — STAGE 5's dry-run will diff against this.

---

## Task 6.1: Append STAGE 5 to runtime-build.yml

**Files:**
- Modify: `.github/workflows/runtime-build.yml` (append a `stage-5-promote` job after `stage-4-overlay`)

**Approach.** A new job `stage-5-promote` runs after both `stage-4-base` and `stage-4-overlay` complete green. It is gated by `if:` to only fire on non-PR events (PR validation must NOT open promote PRs). It downloads the digest artifacts from STAGE 3, reads the base digest from STAGE 2's outputs, performs in-place `sed -E` substitution per overlay name across 5 workflow files, and uses `peter-evans/create-pull-request` to open a single PR.

- [ ] **Step 6.1.1: Add `stage-5-promote` job header.**
  Append the following after the `stage-4-overlay` job (line 778 currently):
  ```yaml
    # -------------------------------------------------------------------------
    # STAGE 5 — promote (digest-bump PR), NEW in Phase 6
    # -------------------------------------------------------------------------
    # Per spec §6.2 STAGE 5 + §9.3. Only one of (push to main / workflow_dispatch)
    # may open a promote PR — PR validation must NOT cascade. The single commit
    # produced bumps all 7 @sha256: occurrences across 5 reusable workflows
    # atomically; consumers see either the new set or the old set, never a mix.
    stage-5-promote:
      name: STAGE 5 — promote (digest-bump PR)
      needs: [stage-2, stage-3-collect, stage-4-base, stage-4-overlay]
      if: github.event_name != 'pull_request'
      runs-on: ubuntu-latest
      timeout-minutes: 10
      concurrency:
        group: stage-5-promote
        cancel-in-progress: false
      permissions:
        contents: write
        pull-requests: write
      steps:
  ```

  `cancel-in-progress: false` is deliberate — we want the in-flight promote to *complete* before the next one starts so each promote PR opens against a fully-bumped baseline, not against partial state. Cancelling an in-flight promote could leave a half-applied substitution in the workspace if cancellation lands mid-step.

- [ ] **Step 6.1.2: Checkout step.**
  ```yaml
        - name: Checkout
          uses: actions/checkout@v5
          with:
            fetch-depth: 1
  ```

- [ ] **Step 6.1.3: Resolve App token for the PR push.**
  We use the App token instead of `GITHUB_TOKEN` so the PR shows up under a bot identity (matches `claude-pr-review.yml`'s pattern) and can re-trigger downstream workflows when merged. Use the SHA from PE-2:
  ```yaml
        - name: Resolve App token
          id: token
          uses: actions/create-github-app-token@<SHA-FROM-PE-2>  # vX.Y.Z
          with:
            app-id: ${{ secrets.APP_ID }}
            private-key: ${{ secrets.APP_PRIVATE_KEY }}
  ```

- [ ] **Step 6.1.4: Capture base digest + strip `sha256:` prefix.**
  STAGE 2 outputs `base_digest` as `sha256:<hex>` (per `docker/build-push-action@v7` convention — see existing strip pattern at lines 534–548). Replicate the same strip + validate logic:
  ```yaml
        - name: Capture base digest (strip prefix + validate)
          env:
            BASE_DIGEST_RAW: ${{ needs.stage-2.outputs.base_digest }}
          run: |
            set -euo pipefail
            BASE_DIGEST="${BASE_DIGEST_RAW#sha256:}"
            if [ "${#BASE_DIGEST}" -ne 64 ] || [ -n "${BASE_DIGEST//[0-9a-fA-F]/}" ]; then
              echo "ERROR base_digest_invalid value=$BASE_DIGEST" >&2
              exit 1
            fi
            echo "BASE_DIGEST=$BASE_DIGEST" >> "$GITHUB_ENV"
  ```

- [ ] **Step 6.1.5: Validate overlay digests from `stage-3-collect`.**
  Same strip + hex-validate pattern, but for the three overlay digests:
  ```yaml
        - name: Capture overlay digests (strip prefix + validate)
          env:
            REVIEW_RAW: ${{ needs.stage-3-collect.outputs.digest_review }}
            FIX_RAW: ${{ needs.stage-3-collect.outputs.digest_fix }}
            EXPLAIN_RAW: ${{ needs.stage-3-collect.outputs.digest_explain }}
          run: |
            set -euo pipefail
            for pair in "REVIEW:$REVIEW_RAW" "FIX:$FIX_RAW" "EXPLAIN:$EXPLAIN_RAW"; do
              name="${pair%%:*}"; raw="${pair#*:}"
              digest="${raw#sha256:}"
              if [ "${#digest}" -ne 64 ] || [ -n "${digest//[0-9a-fA-F]/}" ]; then
                echo "ERROR overlay_digest_invalid name=$name value=$digest" >&2
                exit 1
              fi
              echo "${name}_DIGEST=$digest" >> "$GITHUB_ENV"
            done
  ```

- [ ] **Step 6.1.6: Login to GHCR + capture OCI labels for PR body.**
  Pull each promoted image and extract its OCI labels (`dev.glitchwerks.ci.private_sha`, `dev.glitchwerks.ci.marketplace_sha`, `dev.glitchwerks.ci.cli_version`). These appear in the PR body so reviewers see exactly what's being promoted.
  ```yaml
        - name: Login to GHCR (read)
          uses: docker/login-action@v4
          with:
            registry: ghcr.io
            username: ${{ github.actor }}
            password: ${{ secrets.GITHUB_TOKEN }}

        - name: Capture OCI labels for PR body
          run: |
            set -euo pipefail
            : > /tmp/oci-labels.md
            for pair in "base:$BASE_DIGEST" "review:$REVIEW_DIGEST" "fix:$FIX_DIGEST" "explain:$EXPLAIN_DIGEST"; do
              name="${pair%%:*}"; digest="${pair#*:}"
              ref="ghcr.io/glitchwerks/claude-runtime-${name}@sha256:${digest}"
              docker pull "$ref" >/dev/null
              private_sha=$(docker inspect "$ref" --format '{{ index .Config.Labels "dev.glitchwerks.ci.private_sha" }}')
              marketplace_sha=$(docker inspect "$ref" --format '{{ index .Config.Labels "dev.glitchwerks.ci.marketplace_sha" }}')
              cli_version=$(docker inspect "$ref" --format '{{ index .Config.Labels "dev.glitchwerks.ci.cli_version" }}')
              {
                echo "- **${name}** \`@sha256:${digest:0:12}…\`"
                echo "  - private_sha: \`${private_sha}\`"
                echo "  - marketplace_sha: \`${marketplace_sha}\`"
                echo "  - cli_version: \`${cli_version}\`"
              } >> /tmp/oci-labels.md
            done
  ```

- [ ] **Step 6.1.7: Rewrite digest pins via `sed -E`.**
  Per-overlay regex substitution. The pattern matches the full digest line; the replacement embeds the new digest. Crucially we substitute **per overlay name** so a fix-overlay digest never accidentally lands in a review pin.
  ```yaml
        - name: Rewrite digest pins
          run: |
            set -euo pipefail
            FILES=(
              .github/workflows/claude-pr-review.yml
              .github/workflows/claude-apply-fix.yml
              .github/workflows/claude-lint-failure.yml
              .github/workflows/claude-ci-failure.yml
              .github/workflows/claude-tag-respond.yml
            )
            for f in "${FILES[@]}"; do
              sed -i -E \
                -e "s|claude-runtime-review@sha256:[a-f0-9]{64}|claude-runtime-review@sha256:${REVIEW_DIGEST}|g" \
                -e "s|claude-runtime-fix@sha256:[a-f0-9]{64}|claude-runtime-fix@sha256:${FIX_DIGEST}|g" \
                -e "s|claude-runtime-explain@sha256:[a-f0-9]{64}|claude-runtime-explain@sha256:${EXPLAIN_DIGEST}|g" \
                "$f"
            done
            # Verify exactly 7 occurrences land:
            count=$(grep -E "claude-runtime-(review|fix|explain)@sha256:[a-f0-9]{64}" "${FILES[@]}" | wc -l)
            if [ "$count" -ne 7 ]; then
              echo "ERROR digest_count_mismatch expected=7 actual=$count" >&2
              exit 1
            fi
            echo "digest pin rewrite: $count references updated"
  ```

- [ ] **Step 6.1.8: Open digest-bump PR via `peter-evans/create-pull-request`.**
  Use the SHA from PE-1. Branch name is per-build so reruns recreate it cleanly.
  ```yaml
        - name: Open digest-bump PR
          uses: peter-evans/create-pull-request@<SHA-FROM-PE-1>  # vX.Y.Z
          with:
            token: ${{ steps.token.outputs.token }}
            commit-message: |
              promote: runtime images @${{ github.sha }}

              Atomic digest bump across 5 reusable workflows (7 occurrences).
              See PR body for OCI labels.
            branch: auto/runtime-promote-${{ github.sha }}
            delete-branch: true
            title: "promote: runtime images @${{ github.sha }}"
            body-path: /tmp/oci-labels.md
            labels: |
              automation
              ci
              runtime-promote
  ```
  **Note on PR body construction.** The action takes the file contents as the entire body. Prepend a header to `/tmp/oci-labels.md` before this step so the reviewer sees context first:
  ```yaml
        - name: Build PR body
          run: |
            cat > /tmp/pr-body.md <<EOF
            ## Runtime image promotion @${{ github.sha }}

            Atomic digest bump across 5 reusable workflows (7 \`@sha256:\` occurrences) per spec §6.2 STAGE 5. Merging this PR is the promote.

            ### Promoted images

            EOF
            cat /tmp/oci-labels.md >> /tmp/pr-body.md
            cat >> /tmp/pr-body.md <<EOF

            ### Rollback

            To revert this promote: \`git revert <merge-commit>\` once merged, OR run \`runtime/rollback.yml\` with the prior \`pubsha\` (visible in \`git log\` of the prior \`auto/runtime-promote-*\` PRs).

            🤖 _Generated by Claude Code on behalf of @cbeaulieu-gt_
            EOF
  ```
  And change the action input to `body-path: /tmp/pr-body.md`.

- [ ] **Step 6.1.9: Verify workflow syntax with `actionlint`.**
  ```bash
  actionlint -shellcheck="-S info" .github/workflows/runtime-build.yml
  ```
  Expected: clean exit (no errors). If shellcheck flags any `${{ }}` interpolation in single-quoted strings, add `# shellcheck disable=SC2016` per CLAUDE.md "Key conventions".

- [ ] **Step 6.1.10: Add label-value assertion to STAGE 4 base smoke (`runtime/scripts/smoke-test.sh` section d.5 area).**
  Following the same pattern as the existing `safe.directory` check (post-#199), add a section asserting `org.opencontainers.image.revision` is non-empty and is a valid 40-char hex string. This catches future Dockerfile refactors that accidentally drop or reformat the revision label — which would silently break `runtime-rollback.yml`'s Step 6.3.5a label assertion. Single-line addition; no new dependencies.

- [ ] **Step 6.1.11: Commit STAGE 5 append.**
  ```bash
  git -C I:/github-actions/.worktrees/phase-6-promotion add .github/workflows/runtime-build.yml
  git -C I:/github-actions/.worktrees/phase-6-promotion commit -m "$(cat <<'EOF'
  feat(runtime): append STAGE 5 — atomic digest-bump PR (refs #144)

  Per spec §6.2 STAGE 5 + §9.3. After STAGE 4 succeeds (base + all 3
  overlays smoke green), opens a single PR rewriting all 7 @sha256:
  occurrences across 5 reusable workflows in one commit.

  - Per-overlay-name regex substitution (review/fix/explain digests
    cannot cross-contaminate)
  - PR body lists OCI labels (private_sha, marketplace_sha, cli_version)
    for each promoted image
  - peter-evans/create-pull-request SHA-pinned per CLAUDE.md
  - App-token authenticated so the PR shows under bot identity and
    re-triggers downstream consumer workflows when merged

  Refs #144

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

## Task 6.2: Dry-run STAGE 5

**Goal:** Validate STAGE 5 produces a clean digest-bump PR before merging the Phase 6 PR.

- [ ] **Step 6.2.1: Push the worktree branch.**
  ```bash
  git -C I:/github-actions/.worktrees/phase-6-promotion push -u origin phase-6-promotion
  ```

- [ ] **Step 6.2.2: Trigger `runtime-build.yml` via `workflow_dispatch` against the branch.**
  ```bash
  gh -R glitchwerks/github-actions workflow run runtime-build.yml \
    --ref phase-6-promotion \
    --field images=all
  ```

- [ ] **Step 6.2.3: Monitor the run.**
  ```bash
  gh -R glitchwerks/github-actions run list --workflow=runtime-build.yml --limit 1
  # capture the run ID, then:
  gh -R glitchwerks/github-actions run watch <run-id>
  ```
  Expected sequence: STAGE 1 → STAGE 1c (fixture + determinism) → STAGE 2 → STAGE 3 → STAGE 3-collect → STAGE 4-base + STAGE 4-overlay → **STAGE 5-promote**. STAGE 5 must execute (the `if: github.event_name != 'pull_request'` allows `workflow_dispatch`).

- [ ] **Step 6.2.4: Inspect the auto-generated PR.**
  STAGE 5 will open a PR titled `promote: runtime images @<commit-sha>`. Open it via:
  ```bash
  gh -R glitchwerks/github-actions pr list --state open --label runtime-promote
  ```
  Verify:
  - Diff scope: only `.github/workflows/claude-*.yml` files; exactly 7 lines changed (one per existing digest occurrence).
  - PR body lists 4 images with OCI labels (note: the auto PR body will list base + 3 overlays = 4, but only 3 of those — review/fix/explain — actually appear in the diff because no reusable workflow pins the base image; this is intentional — base is referenced only by FROM in overlay Dockerfiles, not by consumer workflows).
  - Branch name: `auto/runtime-promote-<sha>`.
  - Labels: `automation`, `ci`, `runtime-promote`.

- [ ] **Step 6.2.5: Close the dry-run PR without merging.**
  ```bash
  gh -R glitchwerks/github-actions pr close <pr-number> --comment "Dry-run for Phase 6 (#144) — not merging. Real promote happens after Phase 6 lands."
  gh -R glitchwerks/github-actions pr list --state closed --head auto/runtime-promote-<sha>  # confirm closed
  ```

- [ ] **Step 6.2.6: Record the dry-run PR number in the Phase 6 PR body.**
  When opening the Phase 6 PR (Task 6.10), include `Verified STAGE 5 dry-run via PR #<N> (closed without merge)`.

  **Outcome (2026-05-05):** Dry-run PR was **#207** (closed without merge). Reached via two retry rounds:
  1. Run [25410793517](https://github.com/glitchwerks/github-actions/actions/runs/25410793517) — STAGE 5 push rejected; App `claude-action-runner` lacked `workflows: write` permission.
  2. After org admin granted the scope, run [25411207266](https://github.com/glitchwerks/github-actions/actions/runs/25411207266) — same rejection (installation perm propagation lag).
  3. After installation perm refresh (verified by `verify-app-secrets.yml` probe run [25411361926](https://github.com/glitchwerks/github-actions/actions/runs/25411361926)), run [25411378215](https://github.com/glitchwerks/github-actions/actions/runs/25411378215) — STAGE 5 succeeded, opened PR #207. Diff scope, line count, per-overlay substitution, body, and labels all verified per Step 6.2.4. Tracking issue [#205](https://github.com/glitchwerks/github-actions/issues/205) closed.

  Phase 6 PR body line: `Verified STAGE 5 dry-run via PR #207 (closed without merge; see #205 for App-permission resolution).`

---

## Task 6.3: Author runtime/rollback.yml

**Files:**
- Create: `runtime/rollback.yml`

**Approach.** A `workflow_dispatch`-only workflow taking `target_pubsha` as input. For each of 4 images, query GHCR for the digest currently tagged `:<target_pubsha>` (immutable; never pruned per spec §11.4). Apply the same `sed -E` substitution as STAGE 5 but with the rolled-back digests, and open a PR via `peter-evans/create-pull-request`. Note that rollback only updates the **3 overlay digests** that appear in consumer workflow files — the `:base` digest is referenced only by overlay `FROM` lines in Dockerfiles, so rolling back the base requires a re-build, not a workflow file edit. The plan documents this scope.

- [ ] **Step 6.3.1: Author file header + trigger.**
  ```yaml
  name: runtime-rollback

  on:
    workflow_dispatch:
      inputs:
        target_pubsha:
          description: |
            40-char hex pubsha to roll back to. The workflow validates SHAPE only;
            it does NOT verify that target_pubsha corresponds to a previously-promoted
            build. Reviewers of the resulting rollback PR are the second gate — they
            should confirm via:
              git log --grep='auto/runtime-promote-' main --format=%H
            that target_pubsha appears as a previously-promoted build.

            Authorization model: workflow_dispatch on this workflow + merge approval
            on the resulting PR. Treat workflow_dispatch authority as equivalent to
            rollback authority. If that becomes too permissive, add an allowlist step
            that verifies target_pubsha is in `git log --grep='auto/runtime-promote-'`.
          required: true
          type: string
        dry_run:
          description: "Open the PR as a draft and skip auto-merge. Use for rehearsals."
          required: false
          default: true
          type: boolean

  permissions:
    contents: read

  jobs:
    rollback:
      name: Open rollback PR for ${{ inputs.target_pubsha }}
      runs-on: ubuntu-latest
      timeout-minutes: 10
      permissions:
        contents: write
        pull-requests: write
        packages: read
      steps:
  ```

### Authorization model (Option A — explicit acceptance)

Phase 6 ships rollback with the following gate stack:

1. **`workflow_dispatch` permission** — controls who can invoke the rollback. Default org-member access; tighten via repo settings if the workflow becomes too widely available.
2. **OCI revision label assertion** (Step 6.3.5a) — refuses to open a PR if the resolved digests' `org.opencontainers.image.revision` label does not match `inputs.target_pubsha`. Catches retag drift on existing tags.
3. **Inventory + smoke validation** (Steps 6.3.5b, 6.3.5c) — refuses to open a PR if the rolled-back digests do not satisfy `expected.yaml` or smoke-test.sh. Catches images that were valid at build time but no longer satisfy current expectations.
4. **Human merge approval** — the final gate. Reviewers should verify `target_pubsha` appears in `git log --grep='auto/runtime-promote-' main` before merging. The PR title format `rollback: runtime images @<target_pubsha>` makes this verification explicit.

**Not implemented for Phase 6**: an automated allowlist that asserts `target_pubsha` is in the promote-merge log. If the rollback workflow is ever opened to a wider permission scope, or if a non-zero rollback-attack incidence is observed, that allowlist is the next hardening step. Tracked informally; no follow-up issue filed because the trade-off (workflow_dispatch + reviewer judgment vs. allowlist enforcement) is acceptable for the MVP.

- [ ] **Step 6.3.2: Checkout + token + GHCR login.**
  Same pattern as STAGE 5 steps 6.1.2–6.1.3 + 6.1.6. Reuse the App token via `actions/create-github-app-token` (SHA from PE-2).

- [ ] **Step 6.3.3: Validate `target_pubsha` looks like a commit SHA.**
  ```yaml
        - name: Validate target_pubsha
          env:
            TARGET: ${{ inputs.target_pubsha }}
          run: |
            set -euo pipefail
            if [ "${#TARGET}" -ne 40 ] || [ -n "${TARGET//[0-9a-fA-F]/}" ]; then
              echo "ERROR invalid_target_pubsha value=$TARGET — must be a 40-char git SHA" >&2
              exit 1
            fi
  ```

- [ ] **Step 6.3.4: Resolve the digest of `:<target_pubsha>` for each overlay.**
  Use `docker pull` + `docker inspect` (avoids GHCR REST scope complications):
  ```yaml
        - name: Resolve target digests
          env:
            TARGET: ${{ inputs.target_pubsha }}
          run: |
            set -euo pipefail
            for ov in review fix explain; do
              ref="ghcr.io/glitchwerks/claude-runtime-${ov}:${TARGET}"
              if ! docker pull "$ref" >/dev/null 2>&1; then
                echo "ERROR rollback_target_missing image=claude-runtime-${ov} tag=${TARGET}" >&2
                echo "::error:::<target_pubsha> tag does not exist for $ov — rollback target invalid" >&2
                exit 1
              fi
              # docker inspect Id is the local content digest; for registry digest use RepoDigests
              digest=$(docker inspect "$ref" --format '{{ range .RepoDigests }}{{ . }}{{ "\n" }}{{ end }}' \
                | grep "claude-runtime-${ov}@sha256:" | head -1 \
                | sed -E "s|.*@sha256:||")
              if [ "${#digest}" -ne 64 ] || [ -n "${digest//[0-9a-fA-F]/}" ]; then
                echo "ERROR target_digest_invalid overlay=$ov value=$digest" >&2
                exit 1
              fi
              upper=$(echo "$ov" | tr a-z A-Z)
              echo "${upper}_DIGEST=$digest" >> "$GITHUB_ENV"
              echo "  rollback target $ov -> @sha256:${digest:0:12}…"
            done
  ```

- [ ] **Step 6.3.5: Apply `sed -E` substitution (same as STAGE 5 step 6.1.7).**
  Identical block — 5 files, 3 substitutions per file, 7 occurrences asserted.

- [ ] **Step 6.3.5a: Verify all target digests share the requested `target_pubsha` label.**
  Before opening the PR, assert that the images resolved via `:<target_pubsha>` still carry the expected OCI label. GHCR has tag immutability disabled (per #173) — a `:<pubsha>` tag can be retagged or deleted after the initial push. This step detects tag-retag drift and refuses to roll back to a corrupted target.

  The label to read is `org.opencontainers.image.revision` — the standard OCI label set via `--build-arg PUB_SHA` in the Dockerfile `LABEL` block. (A prior draft of this step used a non-existent custom label name; that was corrected by Pass 2 Charge 1. Verified by reading `runtime/base/Dockerfile` lines 22–29: labels emitted are `org.opencontainers.image.source`, `org.opencontainers.image.revision`, `dev.glitchwerks.ci.private_ref`, `dev.glitchwerks.ci.private_sha`, `dev.glitchwerks.ci.marketplace_sha`, `dev.glitchwerks.ci.cli_version`.)
  ```yaml
        - name: Verify all target digests share the requested target_pubsha label
          shell: bash
          run: |
            # GHCR has tag immutability disabled (per #173). A :<pubsha> tag can be
            # retagged or deleted. Assert that what we resolved still claims to be
            # from the requested pubsha by reading the org.opencontainers.image.revision
            # OCI label on each image — the standard label that holds the pubsha
            # value (set by --build-arg PUB_SHA in the Dockerfile LABEL block).
            for ov in review fix explain; do
              upper=$(echo "$ov" | tr a-z A-Z)
              eval "DIGEST=\${${upper}_DIGEST}"
              LABEL=$(docker manifest inspect "ghcr.io/glitchwerks/claude-runtime-${ov}@${DIGEST}" \
                | jq -r '.config.digest' \
                | xargs -I {} docker inspect --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' "ghcr.io/glitchwerks/claude-runtime-${ov}@${DIGEST}")
              if [ "$LABEL" != "${{ inputs.target_pubsha }}" ]; then
                echo "::error::Overlay $ov resolved digest $DIGEST has revision label '$LABEL', expected '${{ inputs.target_pubsha }}'. Tag retag drift detected — refusing to roll back."
                exit 1
              fi
              echo "  $ov revision label OK: org.opencontainers.image.revision=$LABEL"
            done
  ```

- [ ] **Step 6.3.5b: Run `inventory-match.sh` against target digests.**
  The rolled-back digests must satisfy each overlay's `expected.yaml` inventory contract — the same check STAGE 4-overlay smoke runs at build time. This catches rollback targets that were valid when built but no longer satisfy current expectations (rare but possible if `expected.yaml` was tightened post-build).
  ```yaml
        - name: Run inventory-match against target digests
          shell: bash
          run: |
            # The rolled-back digests must satisfy each overlay's expected.yaml inventory
            # contract — same check STAGE 4-overlay smoke runs at build time. This catches
            # rollback targets that were valid when built but no longer satisfy current
            # expectations (rare but possible if expected.yaml was tightened post-build).
            for ov in review fix explain; do
              upper=$(echo "$ov" | tr a-z A-Z)
              eval "DIGEST=\${${upper}_DIGEST}"
              docker pull "ghcr.io/glitchwerks/claude-runtime-${ov}@sha256:${DIGEST}"
              bash runtime/scripts/inventory-match.sh \
                "ghcr.io/glitchwerks/claude-runtime-${ov}@sha256:${DIGEST}" \
                "runtime/overlays/${ov}/expected.yaml"
            done
  ```

- [ ] **Step 6.3.5c: Run overlay smoke against target digests.**
  Belt-and-braces: also exercise `smoke-test.sh` that STAGE 4 runs. If smoke passes AND inventory-match passes above, the rolled-back digests are validated to the same standard as a fresh build.
  ```yaml
        - name: Run overlay smoke against target digests
          shell: bash
          run: |
            # Belt-and-braces: also exercise the same smoke-test.sh that STAGE 4 runs.
            # If smoke passes here AND inventory-match passes above, the rolled-back
            # digests are validated to the same standard as a fresh build.
            for ov in review fix explain; do
              upper=$(echo "$ov" | tr a-z A-Z)
              eval "DIGEST=\${${upper}_DIGEST}"
              bash runtime/scripts/smoke-test.sh \
                "ghcr.io/glitchwerks/claude-runtime-${ov}@sha256:${DIGEST}" "${ov}"
            done
  ```

- [ ] **Step 6.3.6: Build PR body.**
  ```yaml
        - name: Build PR body
          env:
            TARGET: ${{ inputs.target_pubsha }}
          run: |
            cat > /tmp/pr-body.md <<EOF
            ## Rollback to runtime images @${TARGET}

            Targeted rollback per spec §9.3. Restores all 7 \`@sha256:\` references across 5 reusable workflows to the digest set tagged \`:${TARGET}\` in GHCR.

            ### Restored digests

            - **review** \`@sha256:${REVIEW_DIGEST:0:12}…\`
            - **fix** \`@sha256:${FIX_DIGEST:0:12}…\`
            - **explain** \`@sha256:${EXPLAIN_DIGEST:0:12}…\`

            ### Validation

            - \`:${TARGET}\` tags resolved cleanly via \`docker pull\` for all 3 overlays.
            - sed -E substitution updated exactly 7 occurrences (assertion in workflow).

            🤖 _Generated by Claude Code on behalf of @cbeaulieu-gt_
            EOF
  ```

- [ ] **Step 6.3.6b: Normalize `inputs.dry_run` before opening the PR.**
  GHA expressions do not short-circuit like bash: `false || 'true'` evaluates to `'true'` in a GHA expression context, so reading `inputs.dry_run` directly via an expression and passing it to `peter-evans/create-pull-request`'s `draft:` input can silently invert operator intent. Read the raw input through a shell env var and normalize it explicitly:
  ```yaml
        - name: Normalize inputs.dry_run
          id: mode
          shell: bash
          env:
            RAW_DRY_RUN: ${{ inputs.dry_run }}
          run: |
            set -euo pipefail
            case "${RAW_DRY_RUN:-}" in
              true|"")  NORMALIZED=true ;;
              false)    NORMALIZED=false ;;
              *)
                echo "::error::Invalid inputs.dry_run value: '$RAW_DRY_RUN'. Must be 'true', 'false', or empty."
                exit 1
                ;;
            esac
            echo "dry_run=$NORMALIZED" >> "$GITHUB_OUTPUT"
            echo "rollback dry_run=$NORMALIZED (raw: '$RAW_DRY_RUN')"
  ```

- [ ] **Step 6.3.7: Open rollback PR (draft if `dry_run`).**
  Uses `steps.mode.outputs.dry_run` (from Step 6.3.6b) rather than `inputs.dry_run` directly — avoids the GHA `false || 'true'` evaluation trap.
  ```yaml
        - name: Open rollback PR
          uses: peter-evans/create-pull-request@<SHA-FROM-PE-1>  # vX.Y.Z
          with:
            token: ${{ steps.token.outputs.token }}
            commit-message: "rollback: runtime images @${{ inputs.target_pubsha }}"
            branch: auto/runtime-rollback-${{ inputs.target_pubsha }}
            delete-branch: true
            draft: ${{ steps.mode.outputs.dry_run }}
            title: "rollback: runtime images @${{ inputs.target_pubsha }}"
            body-path: /tmp/pr-body.md
            labels: |
              automation
              ci
              runtime-rollback
  ```

- [ ] **Step 6.3.8: Lint + commit.**
  ```bash
  actionlint -shellcheck="-S info" runtime/rollback.yml
  ```
  Expected: clean. Then:
  ```bash
  git -C I:/github-actions/.worktrees/phase-6-promotion add runtime/rollback.yml
  git -C I:/github-actions/.worktrees/phase-6-promotion commit -m "$(cat <<'EOF'
  feat(runtime): rollback.yml — targeted digest rollback (refs #144)

  Per spec §9.3. workflow_dispatch with target_pubsha input opens a PR
  reverting all 7 @sha256: references to the digest set tagged
  :<target_pubsha> in GHCR. Mirrors STAGE 5's PR mechanism in reverse;
  merging the PR is the rollback.

  - Validates target_pubsha as a 40-char hex SHA before any work
  - Resolves digests via docker pull + inspect RepoDigests
    (avoids GHCR REST scope complications)
  - dry_run: true (default) opens as draft for rehearsal scenarios
  - Same per-overlay regex substitution as STAGE 5 (digest cross-contamination
    is structurally impossible)

  Refs #144

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

## Task 6.4: Dry-run rollback

**Goal:** Verify `rollback.yml` opens a syntactically correct PR. Full end-to-end rehearsal is Task 6.9 (post-merge).

- [ ] **Step 6.4.1: Push the branch (already pushed in 6.2.1).** Skip if 6.2.1 already done.

- [ ] **Step 6.4.2: Trigger rollback against the current production digest set.**
  Pick `target_pubsha` = the commit SHA that currently labels the live overlay tags in GHCR. Find it via:
  ```bash
  docker pull ghcr.io/glitchwerks/claude-runtime-review@sha256:46d16c22e19dcd98bea17827334c28dd0d6f3a97e6c631816fe5741024081aeb
  docker inspect ghcr.io/glitchwerks/claude-runtime-review@sha256:46d16c22e19dcd98bea17827334c28dd0d6f3a97e6c631816fe5741024081aeb \
    --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}'
  ```
  (The pubsha is stored in the standard OCI `org.opencontainers.image.revision` label, set via `--build-arg PUB_SHA` in the Dockerfile. Inspect all labels via `--format '{{ json .Config.Labels }}'` if the value is empty.)

- [ ] **Step 6.4.3: Run rollback.yml in dry-run mode.**
  ```bash
  gh -R glitchwerks/github-actions workflow run runtime/rollback.yml \
    --ref phase-6-promotion \
    --field target_pubsha=<resolved-pubsha> \
    --field dry_run=true
  ```
  Note: `runtime/rollback.yml` is not in `.github/workflows/`, so GitHub Actions will not auto-discover it as a workflow. It must be moved to `.github/workflows/` to be triggerable.

  **DECISION POINT.** The master plan specifies `runtime/rollback.yml` (plain runtime/ path, lines 64–66). But GitHub Actions only auto-detects workflows under `.github/workflows/`. Two options:
  1. **Mirror the file** — keep authoritative copy at `runtime/rollback.yml` AND symlink/copy to `.github/workflows/rollback.yml`.
  2. **Live in `.github/workflows/`** — move authoritative copy to `.github/workflows/runtime-rollback.yml`; the master plan's `runtime/` location is wrong.

  **Choose option 2.** Symlinks behave inconsistently across Windows checkouts and `actions/checkout@v5`. Document this deviation in the Phase 6 PR body and amend the master plan in the same PR.

  **Path corrections:**
  - Task 6.3 file: `.github/workflows/runtime-rollback.yml` (not `runtime/rollback.yml`)
  - Task 6.5 file: `.github/workflows/runtime-check-private-freshness.yml` (not `runtime/check-private-freshness.yml`)
  - Task 6.6 file: `.github/workflows/runtime-prune-pending.yml` (not `runtime/prune-pending.yml`)
  - All three carry `runtime-` prefix to make their relationship to the runtime tree visually obvious in the workflows directory.
  - **Update Task 6.3 step 6.3.1 path before authoring.**

  **Re-run Step 6.4.3 with corrected path:**
  ```bash
  gh -R glitchwerks/github-actions workflow run runtime-rollback.yml \
    --ref phase-6-promotion \
    --field target_pubsha=<resolved-pubsha> \
    --field dry_run=true
  ```

- [ ] **Step 6.4.4: Inspect the dry-run rollback PR.**
  Should be a draft PR with diff matching `git diff main -- .github/workflows/claude-*.yml` showing the digest references reverting to whatever was tagged at `<target_pubsha>`. Since we asked for the CURRENT digest set, the diff should be EMPTY (we're "rolling back" to where we already are). That's the expected sanity-check outcome — empty diff means the resolution path works.

  Close the PR:
  ```bash
  gh -R glitchwerks/github-actions pr close <pr-number> --comment "Dry-run for Phase 6 task 6.4 (#144) — closed unmerged. Empty-diff outcome confirms rollback resolves digests correctly."
  ```

- [ ] **Step 6.4.5: Deliberate-failure rehearsal — prove the failure mode, not just the happy path.**
  Invoke `runtime-rollback.yml` with a `target_pubsha` that does NOT exist in GHCR (use a valid-looking 40-char SHA that was never built, e.g., `0000000000000000000000000000000000000001`):
  ```bash
  gh -R glitchwerks/github-actions workflow run runtime-rollback.yml \
    --ref phase-6-promotion \
    --field target_pubsha=0000000000000000000000000000000000000001 \
    --field dry_run=true
  ```
  Expected: the workflow fails at the "Resolve target digests" step (or at the pubsha-label assertion if the pull somehow succeeds) and does NOT open a PR. Capture the failing run URL. Record this as "deliberate-failure rehearsal" in the Phase 6 PR body. This proves the failure-mode handling is exercised, not just the happy path.

- [ ] **Step 6.4.6: Record outcome in Phase 6 PR body.**

### Task 6.4 deviation (2026-05-05): live dispatch deferred to Task 6.9

**Problem discovered at execution time:** `gh workflow run runtime-rollback.yml --ref phase-6-promotion` returns `HTTP 404: workflow runtime-rollback.yml not found on the default branch`. GitHub indexes `workflow_dispatch` workflows from the **default branch only** — a workflow that exists on a feature branch but not on `main` is invisible to the dispatch API. This is a hard GitHub-side gate, not a CLI quirk.

**Why neither inquisitor pass caught this:** Pass 1 and Pass 2 both reviewed `runtime-rollback.yml`'s logic and the dispatch command syntax; neither pass tested whether the dispatch CLI would actually accept the `--ref phase-6-promotion` invocation against a default-branch-absent workflow. The check is empirical and only surfaces at run time.

**Resolution: Task 6.4 sub-steps 6.4.3 / 6.4.4 / 6.4.5 are deferred to Task 6.9.** Pre-merge, Task 6.4's value reduces to **static validation only**:
- ✅ `actionlint` clean (run during Step 6.3.8)
- ✅ Inquisitor Pass 1 + Pass 2 reviewed the workflow's logic
- ✅ All 5 validation steps (shape → tag exists → revision label → inventory-match → smoke) are visibly chained with explicit error exits

The live empty-diff dry-run + deliberate-failure rehearsal happen as part of Task 6.9 post-merge, where the workflow IS on `main` and the dispatch API accepts the invocation. Task 6.9's existing happy-path (set A → B → roll back → re-promote) and broken-target rehearsal (Step 6.9.7) cover both Step 6.4.3's empty-diff and Step 6.4.5's deliberate-failure intent — no functional loss from this deferral, only timing.

**Considered alternative — rejected:** open a separate PR that merges only the `runtime-rollback.yml` stub to `main`, then dispatch from the feature branch. Adds a merge cycle, splits Phase 6 across two PRs, and creates a window where the workflow exists but the spec/plan references don't yet. Not worth it for a sanity check that's already covered by static validation.

**Phase 6 PR body line:** `Task 6.4 (rollback dry-run): static validation pre-merge (actionlint clean + inquisitor coverage); live dispatch deferred to Task 6.9 post-merge per GitHub workflow_dispatch default-branch-only restriction.`

---

## Task 6.5: Author runtime-check-private-freshness.yml

**File:** `.github/workflows/runtime-check-private-freshness.yml` (path corrected per Task 6.4 decision).

**Approach.** Schedule weekly (`cron: '0 8 * * 1'`); also `workflow_dispatch` with optional `simulate_stale: true` for testing. Reads pinned `ci-v*` from manifest, clones the private repo, computes `git log <pinned-sha>..<main-head> -- <imports_from_private paths>`. If non-empty AND calendar gap > 14 days, opens a `gh issue create` titled `Stale private-ref: ci-v<version> is N days behind main on imported paths`. Idempotent dedupe: search for the exact title before creating.

- [ ] **Step 6.5.1: Author file.**
  ```yaml
  name: runtime-check-private-freshness

  on:
    schedule:
      - cron: "0 8 * * 1"  # Mondays 08:00 UTC
    workflow_dispatch:
      inputs:
        simulate_stale:
          description: "Force-emit a stale issue regardless of actual gap (for rehearsals)."
          required: false
          default: false
          type: boolean

  permissions:
    contents: read
    issues: write

  jobs:
    check:
      name: Check pinned ci-v* against private/main
      runs-on: ubuntu-latest
      timeout-minutes: 5
      steps:
        - name: Checkout this repo
          uses: actions/checkout@v5
          with:
            fetch-depth: 1

        - name: Install yq
          run: |
            set -euo pipefail
            sudo curl -fsSL -o /usr/local/bin/yq \
              https://github.com/mikefarah/yq/releases/download/v4.44.3/yq_linux_amd64
            sudo chmod +x /usr/local/bin/yq

        - name: Read manifest pin
          id: pin
          run: |
            set -euo pipefail
            REF=$(yq -r '.sources.private.ref' runtime/ci-manifest.yaml)
            # Collect imports_from_private path globs, joined for git log -- argument
            mapfile -t SKILLS < <(yq -r '.shared.imports_from_private.skills // [] | .[]' runtime/ci-manifest.yaml)
            mapfile -t AGENTS < <(yq -r '.shared.imports_from_private.agents // [] | .[]' runtime/ci-manifest.yaml)
            CLAUDE_MD=$(yq -r '.shared.imports_from_private.claude_md // "CLAUDE.md"' runtime/ci-manifest.yaml)
            STANDARDS=$(yq -r '.shared.imports_from_private.standards // ""' runtime/ci-manifest.yaml)
            PATHS=()
            for s in "${SKILLS[@]}"; do PATHS+=("skills/$s/"); done
            for a in "${AGENTS[@]}"; do PATHS+=("agents/$a.md"); done
            [ -n "$CLAUDE_MD" ] && PATHS+=("$CLAUDE_MD")
            [ -n "$STANDARDS" ] && PATHS+=("$STANDARDS")
            # Also include overlay-specific imports_from_private (review.inquisitor etc.)
            mapfile -t OV_AGENTS < <(yq -r '.overlays | to_entries | .[] | .value.imports_from_private.agents // [] | .[]' runtime/ci-manifest.yaml)
            for a in "${OV_AGENTS[@]}"; do PATHS+=("agents/$a.md"); done
            echo "ref=$REF" >> "$GITHUB_OUTPUT"
            printf '%s\n' "${PATHS[@]}" > /tmp/import-paths.txt
            echo "import paths to scan:"
            cat /tmp/import-paths.txt

        - name: Resolve App token for claude-configs access
          id: token
          uses: actions/create-github-app-token@<SHA-FROM-PE-2>  # vX.Y.Z
          with:
            app-id: ${{ secrets.APP_ID }}
            private-key: ${{ secrets.APP_PRIVATE_KEY }}
            repositories: claude-configs
          # NOTE: PE-6 must confirm the existing App installation covers
          # glitchwerks/claude-configs before this step is authored.
          # If PE-6 finds the App does NOT cover it, STOP and surface to the
          # user: options are (a) install the App on claude-configs, or (b) add
          # a fine-grained PAT with contents:read on claude-configs as GH_PAT
          # and switch this step back to the env: GH_PAT: pattern.

        - name: Clone claude-configs at pinned ref + main
          env:
            APP_TOKEN: ${{ steps.token.outputs.token }}
          run: |
            set -euo pipefail
            : "${APP_TOKEN:?App token not set — check PE-6 result and APP_ID/APP_PRIVATE_KEY secrets}"
            REF="${{ steps.pin.outputs.ref }}"
            git clone --no-tags \
              "https://x-access-token:${APP_TOKEN}@github.com/glitchwerks/claude-configs" \
              /tmp/private
            git -C /tmp/private fetch --tags origin "$REF"
            PINNED_SHA=$(git -C /tmp/private rev-parse "tags/$REF^{commit}")
            MAIN_SHA=$(git -C /tmp/private rev-parse origin/main)
            PINNED_DATE=$(git -C /tmp/private log -1 --format=%cI "$PINNED_SHA")
            MAIN_DATE=$(git -C /tmp/private log -1 --format=%cI "$MAIN_SHA")
            echo "PINNED_SHA=$PINNED_SHA" >> "$GITHUB_ENV"
            echo "MAIN_SHA=$MAIN_SHA" >> "$GITHUB_ENV"
            echo "PINNED_DATE=$PINNED_DATE" >> "$GITHUB_ENV"
            echo "MAIN_DATE=$MAIN_DATE" >> "$GITHUB_ENV"

        - name: Compute path-scoped commit count + calendar gap
          run: |
            set -euo pipefail
            mapfile -t PATHS < /tmp/import-paths.txt
            cd /tmp/private
            # Path-scoped log per spec §13 Q7
            COMMITS_AHEAD=$(git log --oneline "${PINNED_SHA}..${MAIN_SHA}" -- "${PATHS[@]}" | wc -l)
            DAYS_GAP=$(( ( $(date -d "$MAIN_DATE" +%s) - $(date -d "$PINNED_DATE" +%s) ) / 86400 ))
            echo "COMMITS_AHEAD=$COMMITS_AHEAD" >> "$GITHUB_ENV"
            echo "DAYS_GAP=$DAYS_GAP" >> "$GITHUB_ENV"
            echo "Pinned ref ${{ steps.pin.outputs.ref }}: $COMMITS_AHEAD imported-path commits behind main, $DAYS_GAP days gap"

        - name: Open staleness issue if gap exceeds threshold
          env:
            GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
            REF: ${{ steps.pin.outputs.ref }}
            SIMULATE: ${{ inputs.simulate_stale || 'false' }}
          run: |
            set -euo pipefail
            STALE=false
            if [ "$SIMULATE" = "true" ]; then
              STALE=true
              REASON="simulate_stale=true"
            elif [ "$COMMITS_AHEAD" -gt 0 ] && [ "$DAYS_GAP" -gt 14 ]; then
              STALE=true
              REASON="${COMMITS_AHEAD} imported-path commit(s) ahead, ${DAYS_GAP}d gap > 14d threshold"
            fi
            if [ "$STALE" != "true" ]; then
              echo "Pinned ref is fresh — no issue opened."
              exit 0
            fi
            TITLE="Stale private-ref: ${REF} is ${DAYS_GAP} days behind main on imported paths"
            EXISTING=$(gh -R glitchwerks/github-actions issue list \
              --state open --search "$TITLE in:title" \
              --json number --jq 'length')
            if [ "$EXISTING" -gt 0 ]; then
              echo "Open issue with this title already exists — skipping (idempotent)."
              exit 0
            fi
            BODY=$(cat <<EOF
            Automated freshness check (\`runtime-check-private-freshness.yml\`).

            - **Reason:** $REASON
            - **Pinned ref:** \`$REF\` → \`$PINNED_SHA\` (${PINNED_DATE})
            - **private/main HEAD:** \`$MAIN_SHA\` (${MAIN_DATE})
            - **Imported-path commits ahead:** $COMMITS_AHEAD
            - **Calendar gap:** $DAYS_GAP days

            Path-scoped per spec §13 Q7.

            ### Action

            Cut a new \`ci-v<semver>\` tag in \`glitchwerks/claude-configs\` if the imported paths warrant it, then bump \`sources.private.ref\` in \`runtime/ci-manifest.yaml\` and merge.

            🤖 _Generated by runtime-check-private-freshness.yml_
            EOF
            )
            gh -R glitchwerks/github-actions issue create \
              --title "$TITLE" \
              --label "ci,runtime,stale-private-ref" \
              --body "$BODY"

        # Heartbeat / silent-failure detection: deferred to issue #204 with hard
        # SLA (must land before Phase 7). Until #204 ships, this workflow's silence
        # means EITHER "everything fresh" OR "alarm broken" — operators must monitor
        # run history manually for cron-fire confirmation.
  ```

  **Silent-failure mitigation deferred to #204.** The freshness alarm only emits a signal when there's drift; "no issue" can mean genuinely fresh, OR auth-broke, OR cron-missed-to-fire. Issue #204 commits to building heartbeat detection before Phase 7 begins (hard SLA — Phase 7 work that depends on freshness assumptions cannot proceed until #204 lands). Phase 6 ships the alarm without trip-wire; #204 replaces it with a real heartbeat anchor.

  **Required secrets for Task 6.5:** If PE-6 confirms the existing App covers `glitchwerks/claude-configs`, no new secret is needed — `APP_ID` and `APP_PRIVATE_KEY` already exist from Phase 5. If PE-6 finds the App does NOT cover it, the user must decide between (a) installing the App on `glitchwerks/claude-configs`, or (b) creating a fine-grained PAT with `contents:read` on `glitchwerks/claude-configs` and adding it as `GH_PAT` to repository secrets — in which case `GH_PAT` joins the Required secrets table with rotation owner and date.

- [ ] **Step 6.5.2: Lint.**
  ```bash
  actionlint -shellcheck="-S info" .github/workflows/runtime-check-private-freshness.yml
  ```

- [ ] **Step 6.5.3: Test idempotence path locally (no actual run yet).**
  Visually inspect the `EXISTING=$(gh ... issue list ...)` step — confirm it uses `in:title` modifier so partial-match titles do not collide.

- [ ] **Step 6.5.4: Commit.**
  ```bash
  git -C I:/github-actions/.worktrees/phase-6-promotion add .github/workflows/runtime-check-private-freshness.yml
  git -C I:/github-actions/.worktrees/phase-6-promotion commit -m "$(cat <<'EOF'
  feat(runtime): freshness alarm on private ci-v* pin (refs #144)

  Per spec §11.3 + §13 Q7. Weekly schedule (Mon 08:00 UTC) reads the
  manifest's pinned ci-v* tag, clones glitchwerks/claude-configs, and
  computes git log <pinned>..<main> scoped to imports_from_private paths.
  Opens a deduped issue when (path-scoped commits > 0) AND (calendar gap > 14d).

  - Path-scoped denominator (Q7) — drift on non-imported paths does not page
  - Idempotent dedupe via 'gh issue list --search "<title> in:title"'
  - workflow_dispatch with simulate_stale input for rehearsal
  - 14-day threshold matches spec §11.3; revisit after one cycle

  Refs #144

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

- [ ] **Step 6.5.5: Test rehearsal (post-push, pre-merge).**
  ```bash
  gh -R glitchwerks/github-actions workflow run runtime-check-private-freshness.yml \
    --ref phase-6-promotion \
    --field simulate_stale=true
  ```
  Verify a single staleness issue appears with the expected title format. After confirmation, **close the issue manually** with `gh issue close --comment "Rehearsal for Phase 6 task 6.5 (#144)"`.

  Then run again WITHOUT `simulate_stale`:
  ```bash
  gh -R glitchwerks/github-actions workflow run runtime-check-private-freshness.yml \
    --ref phase-6-promotion
  ```
  Verify NO issue is opened (the pinned ref should be within 14 days, or the path-scoped log empty).

---

## Task 6.6: Author runtime-prune-pending.yml

**File:** `.github/workflows/runtime-prune-pending.yml`.

**Approach.** Schedule daily 02:00 UTC + workflow_dispatch with `dry_run: true` (default) for safety. For each of 4 GHCR packages, list versions tagged `pending-*`, filter where `created_at < now - 30d`, delete via `gh api -X DELETE`. Never touches versions tagged with `:<pubsha>` or `@sha256:` only (untagged digests come from `pubsha` tag deletion, also untouched).

- [ ] **Step 6.6.1: Author file.**
  ```yaml
  name: runtime-prune-pending

  on:
    schedule:
      - cron: "0 2 * * *"
    workflow_dispatch:
      inputs:
        dry_run:
          description: "Log candidates only; do not delete."
          required: false
          default: true
          type: boolean

  permissions:
    contents: read
    packages: write

  jobs:
    prune:
      name: Prune pending-* tags older than 30 days
      runs-on: ubuntu-latest
      timeout-minutes: 10
      strategy:
        fail-fast: false
        matrix:
          package: [claude-runtime-base, claude-runtime-review, claude-runtime-fix, claude-runtime-explain]
      steps:
        - name: List package versions
          env:
            GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          run: |
            set -euo pipefail
            gh api --paginate \
              "/orgs/glitchwerks/packages/container/${{ matrix.package }}/versions" \
              > /tmp/versions.json
            count=$(jq 'length' /tmp/versions.json)
            echo "Total versions for ${{ matrix.package }}: $count"

        - name: Filter pending-* candidates older than 30d
          run: |
            set -euo pipefail
            # CUTOFF expressed as ISO-8601 to compare with created_at strings.
            CUTOFF=$(date -u -d '30 days ago' +%Y-%m-%dT%H:%M:%SZ)
            jq --arg cutoff "$CUTOFF" '
              [.[]
               | select(.metadata.container.tags
                        | map(startswith("pending-"))
                        | any)
               | select(.created_at < $cutoff)
               | {id, name, created_at, tags: .metadata.container.tags}]
            ' /tmp/versions.json > /tmp/candidates.json
            count=$(jq 'length' /tmp/candidates.json)
            echo "Candidates for deletion (pending-* + created_at < $CUTOFF): $count"
            jq -r '.[] | "\(.id)\t\(.created_at)\t\(.tags | join(","))"' /tmp/candidates.json

        - name: Normalize and resolve effective dry-run mode
          id: mode
          shell: bash
          env:
            EVENT_NAME: ${{ github.event_name }}
            RAW_DRY_RUN: ${{ inputs.dry_run }}
          run: |
            set -euo pipefail

            # 1. Normalize the raw input string. GHA's `gh workflow run --field dry_run=X`
            #    accepts X in {true, false, 1, 0, yes, no, ''}. Reject anything outside
            #    {true, false, ''} — fail loud rather than guess.
            #    NOTE: do NOT use `inputs.dry_run || 'true'` — in GHA expressions,
            #    `false || 'true'` evaluates to the string 'true', NOT the boolean false.
            #    An operator who explicitly passes dry_run=false would have their intent
            #    silently reversed. Always normalize via the shell env var instead.
            case "${RAW_DRY_RUN:-}" in
              true|"")  NORMALIZED=true ;;
              false)    NORMALIZED=false ;;
              *)
                echo "::error::Invalid inputs.dry_run value: '$RAW_DRY_RUN'. Must be 'true', 'false', or empty. Refusing to guess."
                exit 1
                ;;
            esac

            # 2. Apply event-source rule: schedule always live-deletes regardless of input.
            #    workflow_dispatch honors the normalized input.
            if [ "$EVENT_NAME" = "schedule" ]; then
              echo "dry_run=false" >> "$GITHUB_OUTPUT"
              echo "Schedule trigger — forcing live-delete (input was '$RAW_DRY_RUN', normalized to '$NORMALIZED', overridden to false)"
            else
              echo "dry_run=$NORMALIZED" >> "$GITHUB_OUTPUT"
              echo "$EVENT_NAME trigger — dry_run=$NORMALIZED (raw input: '$RAW_DRY_RUN')"
            fi

        - name: Delete (or dry-run log)
          env:
            GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
            DRY_RUN: ${{ steps.mode.outputs.dry_run }}
          run: |
            set -euo pipefail
            count=$(jq 'length' /tmp/candidates.json)
            if [ "$count" -eq 0 ]; then
              echo "Nothing to prune for ${{ matrix.package }}."
              exit 0
            fi
            if [ "$DRY_RUN" = "true" ]; then
              echo "DRY_RUN=true — would delete $count version(s) for ${{ matrix.package }}:"
              jq -r '.[] | "  id=\(.id) created=\(.created_at) tags=\(.tags | join(","))"' /tmp/candidates.json
              exit 0
            fi
            jq -r '.[].id' /tmp/candidates.json | while read -r vid; do
              echo "Deleting ${{ matrix.package }} version $vid"
              gh api -X DELETE \
                "/orgs/glitchwerks/packages/container/${{ matrix.package }}/versions/$vid"
            done
            echo "Deleted $count version(s) for ${{ matrix.package }}."
  ```

  **Why explicit normalization instead of `inputs.dry_run || 'true'`:** two separate bugs were fixed here.

  First: `inputs.dry_run || 'true'` resolves to `'true'` on every cron run because `inputs.*` is empty/null in non-dispatch events, making every scheduled run a no-op silent dry-run. The event-source branching (schedule → always live-delete) corrects this.

  Second (caught by Pass 2 Charge 2): in GHA expressions, `false || 'true'` evaluates to the string `'true'`, NOT the boolean `false`. So even in `workflow_dispatch` context, an operator who explicitly passes `dry_run=false` would have their input silently rewritten back to `'true'`, making the live-delete path unreachable. The `case "${RAW_DRY_RUN:-}"` normalization via shell env var corrects this: the GHA expression is read into an env var, the shell sees the literal string `false`, and the case statement maps it to `NORMALIZED=false` correctly.

- [ ] **Step 6.6.2: Lint.**
  ```bash
  actionlint -shellcheck="-S info" .github/workflows/runtime-prune-pending.yml
  ```

- [ ] **Step 6.6.3: Commit.**
  ```bash
  git -C I:/github-actions/.worktrees/phase-6-promotion add .github/workflows/runtime-prune-pending.yml
  git -C I:/github-actions/.worktrees/phase-6-promotion commit -m "$(cat <<'EOF'
  feat(runtime): prune-pending.yml — orphan tag cleanup (refs #144)

  Per spec §9.4. Daily 02:00 UTC across 4 GHCR packages
  (claude-runtime-{base,review,fix,explain}). Lists versions tagged
  pending-*, filters where created_at < now - 30d, deletes via
  GHCR REST. Never touches :<pubsha> or @sha256: refs (immutable
  rollback targets).

  - dry_run: true default for workflow_dispatch (must opt-in to delete)
  - Matrix per package: parallel + isolated failures (fail-fast: false)
  - GITHUB_TOKEN with packages: write covers org-package delete

  Refs #144

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

- [ ] **Step 6.6.4: Dry-run validation — must exercise BOTH branches.**

  **Branch A — `workflow_dispatch` with `dry_run: true`:**
  ```bash
  gh -R glitchwerks/github-actions workflow run runtime-prune-pending.yml \
    --ref phase-6-promotion \
    --field dry_run=true
  ```
  Watch the run. Expected: each matrix cell logs `Total versions: N` and `Candidates for deletion: M` (M may be 0 — Phase 3 was merged 2026-04-30, less than 30 days ago, so no pending tags qualify yet). The "Determine effective dry-run mode" step should log `workflow_dispatch trigger — dry_run=true`. Confirm NOTHING is deleted.

  **Branch B — simulate `github.event_name == 'schedule'` code path locally:**
  Run the mode-detection script stub with the env var override and confirm it would have emitted `dry_run=false`:
  ```bash
  GITHUB_EVENT_NAME=schedule bash -c '
    if [ "$GITHUB_EVENT_NAME" = "schedule" ]; then
      echo "dry_run=false"
      echo "Schedule trigger — live deletes enabled"
    else
      DRY_RUN="${DRY_RUN_INPUT:-true}"
      echo "dry_run=$DRY_RUN"
    fi
  '
  ```
  Expected output: `dry_run=false` and `Schedule trigger — live deletes enabled`. This confirms the cron path would have called the delete API rather than silently no-oping.

  Record both branch verification outcomes in the Phase 6 PR body (Task 6.10).

---

## Task 6.7: Address §13 Q5 — marketplace SHA bump cadence

**Structure change (from Inquisitor Pass 1):** the §13 Q5 spec amendment ships in a standalone PR BEFORE the Phase 6 PR lands, keeping implementation and doc policy separate. Task 6.7 is therefore split into two sub-tasks:

- [ ] **Step 6.7.1a: Open a standalone spec-only PR for §13 Q5.**
  Open a small PR titled `docs(spec): resolve §13 Q5 — marketplace SHA bump cadence` that ONLY amends the spec doc. Contents: one paragraph explaining the decision (manual on observed value) and (if available) a link to wherever the policy was originally agreed (Phase 5 thread, Inquisitor Pass 1, etc.).

  Edit `docs/superpowers/specs/2026-04-21-ci-claude-runtime-design.md` — replace the open Q5 entry:
  ```
  5. **Marketplace sha bump cadence.** When do we bump the pinned marketplace sha? Proposal: manually, on observed value. Document the decision.
  ```
  With:
  ```
  5. ~~**Marketplace sha bump cadence.**~~ **Resolved 2026-05-05 (standalone spec PR, pre-Phase-6).** Manual on observed value; every bump requires the `git diff` review artifact per §10.2 "Marketplace bump review containment". Comment block lives next to `sources.marketplace.ref` in `runtime/ci-manifest.yaml` (added in Phase 6 PR for #144).
  ```

  Commit message: `docs(spec): resolve §13 Q5 — marketplace SHA bump is manual`

  Open and merge this PR before the Phase 6 PR opens. Record the merged PR number as `<Q5-PR-NUMBER>` for Step 6.7.1b.

- [ ] **Step 6.7.1b: Add manifest comment block in Phase 6 PR, referencing the merged §13 Q5 spec PR.**
  In the Phase 6 PR (Task 6.10), add the comment block to `runtime/ci-manifest.yaml` near `sources.marketplace.ref`:
  ```yaml
  sources:
    private:
      repo: glitchwerks/claude-configs
      ref: ci-v0.1.0
    marketplace:
      repo: anthropics/claude-plugins-official
      # Bump cadence: MANUAL on observed value (spec §13 Q5, resolved in PR #<Q5-PR-NUMBER>).
      # Every PR that bumps this SHA MUST include in the body a `git diff`
      # of the marketplace repo between old and new SHA, scoped to plugin
      # paths that appear in the manifest below. See spec §10.2 "Marketplace
      # bump review containment". Automation is intentionally absent —
      # marketplace upstream changes (agent renames, hook schema shifts)
      # require human review before promotion.
      ref: 0742692199b49af5c6c33cd68ee674fb2e679d50
  ```
  The Phase 6 PR body should reference the now-merged §13 Q5 spec PR by number.

- [ ] **Step 6.7.2: Commit manifest comment (as part of Phase 6 PR commits).**
  ```bash
  git -C I:/github-actions/.worktrees/phase-6-promotion add runtime/ci-manifest.yaml
  git -C I:/github-actions/.worktrees/phase-6-promotion commit -m "$(cat <<'EOF'
  docs: §13 Q5 manifest comment — marketplace SHA bump cadence (refs #144)

  Comment block in runtime/ci-manifest.yaml documents the manual-bump
  policy inline, referencing the standalone spec PR that resolved §13 Q5.

  Refs #144

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

## Task 6.8: Address §13 Q4 — forked-PR auth deferral

No code change. The Phase 6 PR body must contain a section documenting:

- [ ] **Step 6.8.1: Prepare PR body text for Q4.**
  Save this snippet for Task 6.10 (PR body construction):
  ```markdown
  ### §13 Q4 — GHCR push from forked PR (deferred)

  Builds are triggered exclusively from `main` (via `push` after merge) or via `workflow_dispatch` from authorized maintainers. Forked PRs cannot trigger `runtime-build.yml` to push to GHCR — there is no v1 use case requiring it. Deferred until the first external fork attempts to contribute runtime content. Tracked as a Phase 7 wrap-up checklist item.

  No workflow changes required for Phase 6.
  ```

  This text appears verbatim in the Phase 6 PR body. Q4 stays open in the spec (no amendment) so the deferral remains visible.

---

## Task 6.9: Rollback rehearsal end-to-end (post-merge)

**This task runs AFTER the Phase 6 PR merges.** The rehearsal cannot happen on the worktree branch because it requires the digest-bump PR (produced by STAGE 5) to land on `main` so consumer workflows actually pick up the new pin.

The rehearsal sequence:

- [ ] **Step 6.9.1: Identify "set A" — the digest set CURRENTLY on `main`.**
  After the Phase 6 PR merges, `main`'s `claude-*.yml` workflows still pin the post-#202 digests (set A — see below). Capture these as `/tmp/set-a.txt` for later comparison.
  ```
  review=46d16c22e19dcd98bea17827334c28dd0d6f3a97e6c631816fe5741024081aeb
  fix=2474e5ce130dca5db44088a5cf1bc22999c0944abf065df47999b018b838b286
  explain=6eb12b4aeca5873e329b6c0542509d87b2dd17eec58ffc3fec47291954c4ff80
  ```

- [ ] **Step 6.9.2: Promote a throwaway "set B".**
  Trigger a no-op build to produce a new digest set:
  ```bash
  gh -R glitchwerks/github-actions workflow run runtime-build.yml \
    --ref main --field images=all
  ```
  Wait for STAGE 5 to open a `promote: runtime images @<pubsha-B>` PR. Inspect the diff — should be 7 line changes across the 5 reusable workflows. **Merge** this PR. Capture the digest set as `/tmp/set-b.txt`.

- [ ] **Step 6.9.3: Observe boot of set B.**
  Open a trivial doc-only PR in this repo. The `claude-pr-review.yml` run on that PR will pull set B's review overlay. Verify in the GHA log:
  ```
  Pulling ghcr.io/glitchwerks/claude-runtime-review@sha256:<set-B-review-digest>
  ```
  matches set B's review digest exactly. Capture the run URL.

- [ ] **Step 6.9.4: Run `runtime-rollback.yml` to revert to set A.**
  ```bash
  gh -R glitchwerks/github-actions workflow run runtime-rollback.yml \
    --ref main --field target_pubsha=<pubsha-A> --field dry_run=false
  ```
  A non-draft `rollback: runtime images @<pubsha-A>` PR appears. Inspect — diff should match `/tmp/set-a.txt`. **Merge** this PR.

- [ ] **Step 6.9.5: Observe boot of set A (the rolled-back state).**
  Open another trivial doc-only PR. Verify the `claude-pr-review.yml` run pulls set A's review digest. Capture URL.

- [ ] **Step 6.9.6: Re-promote back to set B (or a fresh set C) to leave HEAD in a forward state.**
  ```bash
  gh -R glitchwerks/github-actions workflow run runtime-build.yml --ref main --field images=all
  ```
  Merge the resulting `promote:` PR.

- [ ] **Step 6.9.7: Rehearse a rollback to a deliberately-broken target.**
  Pick a `target_pubsha` whose `:<pubsha>` tags were deleted (or never existed). If no such SHA is naturally available, use a random 40-char hex string. Invoke `runtime-rollback.yml` with that SHA:
  ```bash
  gh -R glitchwerks/github-actions workflow run runtime-rollback.yml \
    --ref main \
    --field target_pubsha=<nonexistent-sha> \
    --field dry_run=true
  ```
  Expected: workflow fails at the resolve step (or at inventory-match / pubsha-label assertion) and does NOT open a PR. Capture the failing run log. Append the rehearsal write-up to the post-merge PR body alongside the happy-path rehearsal write-up from Step 6.9.6.

- [ ] **Step 6.9.8: Append rehearsal write-up to Phase 6 PR body.**
  Even though the Phase 6 PR is already merged, GitHub allows editing closed PR bodies via `gh pr edit`. Append a new section that covers both the happy-path rehearsal (steps 6.9.2–6.9.6) and the broken-target rehearsal (step 6.9.7):
  ```markdown
  ## Rollback rehearsal (task 6.9)

  ### Happy path

  | Step | Pubsha | PR | Observed digest in consumer | Time |
  |---|---|---|---|---|
  | Set A baseline | `<sha-A>` | (existing) | review=`<digest-A>` | … |
  | Promote set B | `<sha-B>` | #N1 | review=`<digest-B>` | … |
  | Observe boot of B | — | run URL #R1 | review=`<digest-B>` ✓ | … |
  | Rollback to A | `<sha-A>` | #N2 | review=`<digest-A>` | … |
  | Observe boot of A | — | run URL #R2 | review=`<digest-A>` ✓ | … |
  | Re-promote set C | `<sha-C>` | #N3 | review=`<digest-C>` | … |

  No surprises. Total wall clock: <X> minutes from set-B promote to set-A consumer-visible.

  ### Broken-target rehearsal (step 6.9.7)

  | Target pubsha | Expected failure | Actual failure step | PR opened? |
  |---|---|---|---|
  | `<nonexistent-sha>` | Resolve step / pubsha-label assertion | <actual> | No |

  ```

  Run:
  ```bash
  gh -R glitchwerks/github-actions pr edit <phase-6-pr-number> --body-file /tmp/updated-phase-6-body.md
  ```

---

## Task 6.10: Open Phase 6 PR (Closes #144)

- [ ] **Step 6.10.1: Update CLAUDE.md "CI Runtime" section.**
  Append a paragraph after the existing "Phase 3 status" paragraph:
  ```markdown
  **Phase 6 status:** STAGE 5 of `runtime-build.yml` opens an atomic digest-bump PR after every successful build (5 reusable workflows, 7 `@sha256:` occurrences in one commit). Image promotion PR creation is fully automated; merging the promote PR is a human review step (#203 tracks the auto-merge follow-up). Three runtime-tooling workflows under `.github/workflows/runtime-*.yml` provide the operational safety net: `runtime-rollback.yml` (workflow_dispatch with `target_pubsha`), `runtime-check-private-freshness.yml` (weekly cron, path-scoped denominator per spec §13 Q7), and `runtime-prune-pending.yml` (daily cron, deletes `pending-*` tags older than 30 days; never touches `:<pubsha>` or `@sha256:` refs). Promote and rollback PRs are authored by App-token; consumers see the bot identity. Issue [#144](https://github.com/glitchwerks/github-actions/issues/144).
  ```

- [ ] **Step 6.10.2: Update README.md "CI runtime" section.**
  Append:
  ```markdown
  #### Promotion + rollback (Phase 6)

  Image promotion PR creation is fully automated; merging the promote PR is a human review step (#203 tracks the auto-merge follow-up). Every `main`-pushed `runtime/**` change triggers a build; if all four images smoke green, STAGE 5 opens a `promote: runtime images @<pubsha>` PR atomically updating all 7 digest pins across the 5 reusable workflows. Merging that PR is the promotion.

  - **Targeted rollback:** dispatch `runtime-rollback.yml` with `target_pubsha=<prior-commit-sha>`. Opens a PR reverting digests to whatever was tagged `:<target_pubsha>` in GHCR.
  - **Standard rollback:** `git revert <promote-merge-commit>` produces an equivalent atomic restore.
  - **Freshness alarm:** `runtime-check-private-freshness.yml` runs Mondays 08:00 UTC; opens a deduped issue if the pinned `ci-v*` tag is > 14 days behind `main` on imported paths.
  - **Orphan cleanup:** `runtime-prune-pending.yml` runs daily 02:00 UTC; deletes `pending-*` tags older than 30 days across all 4 packages.
  ```

- [ ] **Step 6.10.3: Commit doc updates.**
  ```bash
  git -C I:/github-actions/.worktrees/phase-6-promotion add CLAUDE.md README.md
  git -C I:/github-actions/.worktrees/phase-6-promotion commit -m "$(cat <<'EOF'
  docs: Phase 6 status block in CLAUDE.md + README runtime section (refs #144)

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

- [ ] **Step 6.10.4: Push + open PR.**
  ```bash
  git -C I:/github-actions/.worktrees/phase-6-promotion push -u origin phase-6-promotion
  ```
  Then open the PR via `mcp__github__create_pull_request` (router writes — never the `gh` CLI for this) with:
  - Title: `Phase 6: STAGE 5 promote PR + rollback + freshness alarm + prune`
  - Base: `main`
  - Head: `phase-6-promotion`
  - Draft: `true` (mark ready after CI green)
  - Body: composed from sections including:
    - Summary (3-5 bullets)
    - Files added/modified (7 listed)
    - Verification table (dry-run links from 6.2/6.4/6.5/6.6)
    - §13 Q4 deferral text from Step 6.8.1
    - §13 Q5 resolution note (links to merged standalone spec PR + manifest comment block)
    - §13 Q7 implementation note (path-scoped denominator)
    - "Rollback rehearsal pending — task 6.9 to be appended post-merge"
    - **`Closes #144`** as plain text (NOT inside a code fence — per CLAUDE.md "PR body must contain the closing keyword")
    - Attribution: `🤖 _Generated by Claude Code on behalf of @cbeaulieu-gt_`

- [ ] **Step 6.10.5: Mark ready after CI green.**
  Wait for the `lint.yml` workflow + any path-filtered `runtime-build.yml` STAGE 1 (no STAGE 5 since it's a PR event) to complete. Then:
  ```bash
  gh -R glitchwerks/github-actions pr ready <pr-number>
  ```

- [ ] **Step 6.10.6: Address bot review (`claude-pr-review.yml`) before merge.**
  Per CLAUDE.md "CRITICAL — check and evaluate PR review feedback before merging":
  - **Phase 6 ships Option A: human-in-loop merge.** Every weekly promote PR is reviewed and merged by a maintainer. The PR's atomic substitution + per-overlay regex isolation guarantees still hold; the gate is the human merge, not bot automation. Issue #203 tracks the Option C evolution (auto-merge with quality-gate self-validation) — explicitly out of scope for #144.
  - Fetch live state: `mcp__github__get_pull_request` (delegate to the `ops` agent per CLAUDE.md "GitHub Read/Write Split")
  - Inspect inline comments + general conversation
  - Address any `Critical` / `BLOCKING` / `High-Priority` / `MAJOR` items via `gh-pr-review-address` skill
  - Re-verify CI green AFTER fixes land
  - Squash-merge: `mcp__github__merge_pull_request` with `merge_method: SQUASH`

---

## Self-review checklist

- [x] **Spec coverage** — every Phase 6 spec section + master plan task maps to a numbered task here:
  - §6.2 STAGE 5 → Task 6.1
  - §9.3 Rollback → Task 6.3
  - §9.4 Prune → Task 6.6
  - §11.3 Freshness → Task 6.5
  - §13 Q4 → Task 6.8 (PR body deferral)
  - §13 Q5 → Task 6.7 (standalone spec PR pre-Phase-6 + manifest comment in Phase 6 PR referencing it)
  - §13 Q7 → Task 6.5 (path-scoped denominator implementation)
  - Master plan tasks 6.1–6.9 → Tasks 6.1–6.9 here
  - Validation tasks 6.2 / 6.4 / 6.5.5 / 6.6.4 covered
  - Rollback rehearsal 6.9 covered (post-merge)
  - **Rollback authorization** — Option A documented in Task 6.3 (workflow_dispatch + reviewer judgment + label/inventory/smoke gates). No allowlist enforcement.

- [x] **Placeholder scan** — `<SHA-FROM-PE-1>` and `<SHA-FROM-PE-2>` appear deliberately as substitution markers gated by Pre-execution checks PE-1 / PE-2. No "TBD"/"figure it out later". Path-correction at Task 6.4 explicit (deviates from master plan; deviation documented in PR body).

- [x] **Type/name consistency** — every workflow file uses `runtime-` prefix in `.github/workflows/` (Path correction in Task 6.4). Digest variables consistently `BASE_DIGEST` / `REVIEW_DIGEST` / `FIX_DIGEST` / `EXPLAIN_DIGEST` (uppercase + `_DIGEST` suffix). Issue references `#144` plain-text per CLAUDE.md.

- [x] **Dependency graph** — Task ordering: PE-1..5 → 6.1 → 6.2 (validates 6.1) → 6.3 (uses 6.4 path correction) → 6.4 → 6.5 → 6.6 → 6.7 → 6.8 → 6.10 (PR opening) → merge → 6.9 (post-merge rehearsal). 6.5 and 6.6 are independent of 6.1/6.3 and could be parallel-authored if desired. (Task 6.11 was deleted on 2026-05-05 when #143 was closed; no longer referenced here.)

- [x] **§13 coverage** — Q4 deferred (PR body), Q5 resolved (standalone spec PR pre-Phase-6; manifest comment in Phase 6 PR references it by PR number), Q7 implemented (path-scoped). Q1/Q2/Q3/Q8/Q9/Q10 already resolved in earlier phases.

---

## Highest-risk items (read these before signing off)

1. **Path deviation from master plan (Task 6.4 decision).** Master plan files at `runtime/rollback.yml` etc. — but GHA only auto-discovers under `.github/workflows/`. Plan moves them to `.github/workflows/runtime-*.yml` and amends master plan in same PR. **Approved 2026-05-05.** The Phase 6 PR amends the master plan in the same commit.

2. **App-token requirement for STAGE 5 + rollback PRs.** `APP_ID` + `APP_PRIVATE_KEY` secrets must already exist (Phase 5 confirmed they do, since `claude-pr-review.yml` uses them). If either is rotated, both STAGE 5 and `runtime-rollback.yml` break silently — the workflow would log an auth error but no PR would appear. Mitigation: any rotation must include re-running `runtime-build.yml` to confirm STAGE 5 still works.

3. **Rollback rehearsal (Task 6.9) modifies `main`.** It promotes a real set B, rolls back to A, then re-promotes. **Three** real merges to `main`. Each one re-triggers downstream consumer workflows. Risk: if any of those merges happens during a maintenance window incident, the rehearsal compounds the problem. Mitigation: run 6.9 only in a quiet window with a clear "incident-free" baseline.

4. **GHCR REST API scope assumptions (PE-3).** `GITHUB_TOKEN` with `packages: write` covers org-package delete in MOST cases, but enterprise org policies can restrict this. If `runtime-prune-pending.yml`'s delete step fails with 403, the fallback is a PAT with `delete:packages`. Plan does not pre-provision this; it would be a follow-up if needed.

5. **Empty-diff rollback dry-run (Task 6.4 step 6.4.4) is structurally correct but doesn't exercise the substitution code path.** Task 6.4.5 (deliberate-failure rehearsal) was added in the Pass 1 Charge 5 fold to address this — it invokes rollback with a `target_pubsha` that does NOT exist in GHCR, asserting the workflow refuses to open a PR. Combined with Step 6.9.7's broken-target rehearsal post-merge, the substitution path IS exercised. **Resolved 2026-05-05.**

6. **Rollback workflow's pubsha-revision-label assertion depends on `org.opencontainers.image.revision` continuing to carry the pubsha value.** The Dockerfile sets this via `--build-arg PUB_SHA`. If a future Dockerfile refactor changes how the revision label is populated (e.g., switches to `${{ github.sha }}` directly), the rollback assertion silently breaks — this is the same class of bug Pass 2 Charge 1 caught and corrected. Mitigation: STAGE 4 smoke should add a label-value assertion (covered by Step 6.1.10, added on 2026-05-05).

7. **`actions/create-github-app-token` `repositories:` scope for cross-repo clone (Charge 4 / PE-6).** If PE-6 confirms the App does NOT cover `glitchwerks/claude-configs`, Task 6.5 requires either (a) installing the App on that repo or (b) provisioning a new `GH_PAT` secret. Either path requires out-of-band action before Task 6.5 can be executed. If this blocker is discovered mid-implementation, pause and surface it — do not fall back to a hard-coded PAT without user confirmation.

   Sub-risk: the freshness alarm itself has no silent-failure detection in Phase 6 (Charge 4 deferred to #204). If the alarm's auth breaks between Phase 6 ship and #204 landing, the silent failure is invisible. Mitigation during the gap: an operator should manually check `gh run list --workflow=runtime-check-private-freshness --limit 5` weekly until #204 lands.

---

## Execution handoff

Plan complete and saved to `docs/superpowers/plans/phase-6-promotion.md`. Approved execution mode (2026-05-05): **mixed inline + subagent**.

- **Inline (router-driven):** Tasks 6.1–6.4 — STAGE 5 promote job + dry-run, rollback workflow + dry-run. These touch the digest-substitution regex pattern that asserts exactly 7 occurrences land per pass; isolated context per step matters more than fast iteration.
- **Subagent-driven:** Tasks 6.5–6.8 — freshness alarm, prune-pending, §13 Q5 manifest comment, §13 Q4 deferral text. Lower-risk, more rote authoring; subagent isolation gives clean per-task context.
- **Inline:** Tasks 6.10 (PR opening) and 6.9 (post-merge rehearsal) — both need router judgment for live coordination.

---

## Plan refresh log

### 2026-05-05 — pre-execution refresh

The plan was authored on 2026-05-02 against repo state at commit `671c875` (Phase 5 merge). Between authoring and execution start, the following happened in the same parent session and required a pre-execution refresh:

- **#143 manually closed.** Phase 5's epic-level issue was closed via `gh issue close 143 --reason completed` after confirming the work shipped via PR #189. **Effect:** Task 6.11 (housekeeping) is moot and was deleted; the `Closes #143` reference in Step 6.10.4 PR body was removed.
- **PR #200 merged.** Baked `git config --system --add safe.directory '*'` into `runtime/base/Dockerfile` (closes #197, #199). Triggered runtime-build run `25405636887` which rebuilt the base + all 3 overlays. **Effect:** new digests entered the canonical pinned state.
- **PR #202 merged.** Repointed all 5 reusable workflows + claude-tag-respond dispatch map to the post-#200 digests (closes #201). **Effect:** `main`'s `claude-*.yml` files now pin the post-#200 digests, NOT the Phase-5-era ones the original plan referenced.
- **v2.2.0 released.** Tagged at commit `2bc06c5`; `v2` floating tag moved. The Phase 6 PR will be the next consumer-facing change after v2.2.0; no version bump required during Phase 6 (Phase 6 is internal automation, not a consumer-API change).

The set-A digest values in Step 6.9.1 were updated from the stale Phase-5-era stubs (review / fix / explain abbreviated digests that appeared in the original plan) to the current pinned values:

```
review=46d16c22e19dcd98bea17827334c28dd0d6f3a97e6c631816fe5741024081aeb
fix=2474e5ce130dca5db44088a5cf1bc22999c0944abf065df47999b018b838b286
explain=6eb12b4aeca5873e329b6c0542509d87b2dd17eec58ffc3fec47291954c4ff80
```

(`base=0a1f06f1157b26fd2b93293c3b249fd778980c4ec0c273d2d6046e2ea6b4459c` is recorded for completeness; the rollback rehearsal targets overlays.)

Path deviation (`runtime/*.yml` → `.github/workflows/runtime-*.yml`) — **approved 2026-05-05**. Execution mode — **mixed inline + subagent, approved 2026-05-05**.

Inquisitor passes 1 + 2 are scheduled to run after this refresh, before the plan is committed.

### 2026-05-05 — Inquisitor Pass 1 triage

Adversarial review (1 of 2 scheduled passes) surfaced 6 charges. Disposition:

| # | Severity | Charge | Disposition |
|---|---|---|---|
| 1 | Critical | STAGE 5 concurrency race | Folded — concurrency guard added to Task 6.1 |
| 2 | Critical | Branch protection × bot promote PR | Resolved as Option A (human-in-loop). Option C (auto-merge with quality-gate self-validation) tracked as #203 follow-up. Plan copy reframed; `Closes #203` NOT added to Phase 6 PR |
| 3 | High | `runtime-prune-pending.yml` cron-path dry-run lock-in | Folded — event-source branching in Task 6.6 + dual-branch validation |
| 4 | High | Undeclared `GH_PAT` secret | Folded — PE-6 added (verify App coverage of claude-configs); if covered, use App token; if not, surface to user |
| 5 | High | Rollback workflow doesn't validate target digests | Folded — pre-PR `inventory-match.sh` + smoke + pubsha-label-drift assertion in Task 6.3; deliberate-failure rehearsal in Task 6.4.5 + 6.9.7 |
| 6 | Medium | §13 Q5 spec amendment in same PR as implementation | Folded-light — Task 6.7 split: standalone spec PR before Phase 6, manifest comment references it |

Pass 2 of inquisitor review is queued before plan commit. Pass 2 charges may surface what Pass 1 missed; plan stays untracked until Pass 2 triage completes.

### 2026-05-05 — Inquisitor Pass 2 triage

Adversarial review pass 2 of 2 surfaced 5 charges. Pass 2 specifically caught two regressions introduced by Pass 1 fixes (Charges 1 and 2 below) — exactly what `feedback_inquisitor_twice_for_large_design.md` predicts the second pass catches.

| # | Severity | Charge | Disposition |
|---|---|---|---|
| 1 | Critical | Pass 1 Charge 5 fix referenced a non-existent custom OCI label; Dockerfiles actually emit `org.opencontainers.image.revision` for the pubsha value | Folded — label name corrected in Step 6.3.5a; Highest-risk #6 rewritten |
| 2 | Critical | GHA expression `\|\|` doesn't short-circuit like bash; `inputs.dry_run \|\| 'true'` always rewrites falsey-but-explicit `false` back to `'true'` | Folded — explicit normalization step in both Task 6.6.1 (prune) and Task 6.3 (rollback via Step 6.3.6b); PE-7 added |
| 3 | High | `target_pubsha` validated as hex but not as previously-promoted SHA | Resolved as Option A (explicit acceptance — workflow_dispatch authority + reviewer judgment + label/inventory/smoke gates). No allowlist enforcement; documented in Task 6.3 "Authorization model" section |
| 4 | High | Heartbeat for freshness alarm is a stub, not a heartbeat | Resolved as Option B — stub removed in Task 6.5; replaced with deferral comment pointing at #204 (hard SLA — blocks Phase 7) |
| 5 | Medium | Self-review + Highest-risk staleness; disabled-plugin MCP tool namespace referenced in Task 6.10.6; STAGE 4 label-value assertion gap | Folded — Self-review updated, Highest-risk #5 marked resolved, MCP tool name fixed to `mcp__github__get_pull_request` in Task 6.10.6, new Step 6.1.10 adds STAGE 4 label assertion |

Plan is now ready for commit. No third pass scheduled — the two Pass 2 Criticals were structural typos with clear fixes, not architectural ambiguities. Proceeding to lock-and-execute after this fold lands.
