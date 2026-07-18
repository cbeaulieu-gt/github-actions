# Consumer Onboarding: Wiring Claude-Powered CI into a glitchwerks Repo

This document walks an engineer through the full setup arc for adding Claude-powered CI automation to a new intra-`glitchwerks`-org repository. It covers secrets, the GitHub App, GHCR package access, and dropping in the caller workflow file. Budget **15–30 minutes** for a first-time setup; 5–10 minutes once you have done it before.

**Just want the YAML?** Skip ahead to [`examples/`](../examples/) — the five drop-in templates are there with inline comments. Come back here if something does not work.

---

## Prerequisites

Before starting, confirm each item:

- [ ] The consumer repo exists in the `glitchwerks` GitHub organization.
- [ ] You have admin access to the consumer repo, or someone who does is available.
- [ ] You have org-admin access to `glitchwerks`, or a contact who does — a few steps (org secrets, package visibility) require it.
- [ ] The GitHub App `claude-action-runner` (or whichever App your team uses to back `APP_ID`/`APP_PRIVATE_KEY`) is available. See [Step 2](#step-2--create--install-the-github-app) if you are not sure whether one exists.
- [ ] The three GHCR overlay packages (`claude-runtime-review`, `claude-runtime-fix`, `claude-runtime-explain`) have **Internal** visibility set at the org level — this was done org-wide on 2026-05-06. Verify with the command in [Step 3](#step-3--verify-ghcr-package-access) in case it was reverted.

---

## Step 1 — Decide your secret strategy

Three secrets must be available to the consumer repo's Actions runner:

| Secret | Purpose |
|---|---|
| `CLAUDE_CODE_OAUTH_TOKEN` | Authenticates all `claude-code-action` invocations |
| `APP_ID` | GitHub App ID — used to generate short-lived tokens for git push and API calls |
| `APP_PRIVATE_KEY` | GitHub App private key (PEM format) |

### Org-level vs per-repo secrets

| Approach | Pros | Cons |
|---|---|---|
| **Org-level** (recommended) | Rotate once, all consumers get the new value automatically | Requires org-admin to create; must scope visibility to "Selected repositories" to prevent leakage |
| **Per-repo** | Stronger isolation per consumer | Every new consumer repo needs the secrets added individually |

**Recommendation:** use org-level secrets with visibility set to "Selected repositories." Add your two test-case consumer repos initially; expand the selection as you roll out.

### Concrete click-path (org-level)

1. Open `https://github.com/organizations/glitchwerks/settings/secrets/actions`.
2. Click **New organization secret**.
3. Name the secret (e.g. `CLAUDE_CODE_OAUTH_TOKEN`), paste the value.
4. Under **Repository access**, choose **Selected repositories** and add the consumer repo(s).
5. Click **Add secret**. Repeat for `APP_ID` and `APP_PRIVATE_KEY`.

---

## Step 2 — Create / install the GitHub App

See the **GitHub App setup** section in the [main README](../README.md#github-app-setup) for the full creation and installation steps. This doc does not duplicate that content.

**Key requirements for write-capable workflows** (tag respond, lint failure, CI failure, apply fix):

- The App must be installed on every consumer repo.
- The App needs **Contents: read and write** and **Pull requests: read and write** repository permissions.

**PEM newline footgun:** when pasting `APP_PRIVATE_KEY` into a GitHub secret, preserve the leading and trailing newlines of the PEM block exactly as they appear in the `.pem` file. Clipboards, text editors, and form fields frequently strip them. A truncated or newline-stripped key produces a runtime error like:

```
error:1E08010C:DECODER routines::unsupported
```

at the "Resolve write token" step. This error is slow to diagnose because it looks like an auth failure rather than a malformed key. Re-paste directly from the original `.pem` file if you see it.

---

## Step 3 — Verify GHCR package access

Run these three commands from any terminal with `gh` authenticated as an org member **before** adding the workflow file:

```bash
gh api -H "Accept: application/vnd.github+json" \
  /orgs/glitchwerks/packages/container/claude-runtime-review \
  | jq '.visibility'

gh api -H "Accept: application/vnd.github+json" \
  /orgs/glitchwerks/packages/container/claude-runtime-fix \
  | jq '.visibility'

gh api -H "Accept: application/vnd.github+json" \
  /orgs/glitchwerks/packages/container/claude-runtime-explain \
  | jq '.visibility'
```

Each should print `"internal"`. If any package returns `"private"` instead:

1. Open `https://github.com/orgs/glitchwerks/packages/container/<package-name>/settings`.
2. Click **Change package visibility** → **Internal**.
3. Re-run the verification command above.

**Why this matters:** the reusable workflows pull an overlay image from GHCR before any job step runs. If the package is `private` and the consumer repo has not been granted explicit access, the runner returns `manifest unknown` — an authorization-masked error that looks like the image does not exist. See issue [#192](https://github.com/glitchwerks/github-actions/issues/192) for the original diagnosis.

**Per-repo fallback (if Internal visibility cannot be set):** go to the package settings page → **Manage Actions access** → add the consumer repo with role **Read**. Repeat for all three packages.

---

## Step 4 — Drop in your caller workflow

### Pick the right template

| What you want Claude to do | Template to copy |
|---|---|
| Respond to `@claude` mentions in PR and issue comments | `examples/claude-tag-respond.yml` |
| Diagnose (and optionally fix) lint failures on a PR | `examples/claude-lint-failure.yml` |
| Diagnose (and optionally fix) CI failures | `examples/claude-ci-failure.yml` |
| Apply a unified diff to a PR branch (manual trigger) | `examples/claude-apply-fix.yml` |

### Copy the template

The `examples/` directory lives in `glitchwerks/github-actions`, not in the consumer repo. Copy the file into the consumer repo's `.github/workflows/` directory:

```bash
# From inside the consumer repo
curl -O --output-dir .github/workflows/ \
  https://raw.githubusercontent.com/glitchwerks/github-actions/main/examples/<file>.yml
```

Or copy it manually from a local clone of `glitchwerks/github-actions`.

### Adjust two values

Once the file is in place, the only inputs you typically need to tune are:

```yaml
    with:
      model: claude-opus-4-5   # default: claude-sonnet-4-5 — upgrade for harder tasks
      max_turns: '20'           # default: 15 — increase for complex codebases
```

Everything else — secrets wiring, trigger events, concurrency, container pins — is already correct in the template.

### Do not strip `packages: read`

Every template's `permissions:` block includes `packages: read`. This is required for the implicit `docker pull` that runs before any step. GitHub does not provide a meaningful error if this permission is absent — the pull silently fails with `manifest unknown`. Leave the full permissions block intact.

---

## Step 5 — First-run smoke checklist

### Event-driven templates

Use this checklist for `claude-tag-respond.yml`, `claude-lint-failure.yml`, and `claude-ci-failure.yml`. It does not apply to the manually dispatched `claude-apply-fix.yml` template.

After committing the workflow file to the consumer repo's default branch (or a PR):

1. **Open a tiny test PR.** A one-line README change is sufficient. Mark it "ready for review" (not draft).
2. **Wait ~2–3 minutes.** The Actions runner must pull the container image on first run; subsequent runs are faster.
3. **Check the PR timeline.** Expect a Claude comment posted by your App's bot identity.
4. **Check the Actions tab.** The workflow run should show as `success`. If it is `failure`, open the run and read the first failed step.

If no comment appears after 5 minutes, proceed to [Step 6](#step-6--common-footguns).

### Apply Fix (manual dispatch)

After committing `claude-apply-fix.yml` to the consumer repo's default branch, dispatch it manually for a test PR:

```bash
gh workflow run claude-apply-fix.yml \
  -f pr_number=42 \
  -f fix_description="Fix missing null check in auth handler" \
  -f fix_diff="$(cat my.patch)"
```

Check the Actions tab for a successful run, then verify that the applied commit appears on the PR branch. This workflow does not post a PR-timeline comment in response to a PR event.

---

## Step 6 — Common footguns

### `manifest unknown` error

**Symptom:** the workflow run fails immediately with a message like:

```
Error response from daemon: manifest unknown
```

**Causes and fixes (try in order):**

1. Missing `packages: read` in the workflow-level `permissions:` block — add it.
2. Consumer repo not on the package access list — check the package settings page and add the repo with role **Read**, or set visibility to **Internal** (see [Step 3](#step-3--verify-ghcr-package-access)).
3. Package visibility was reverted to `private` — re-run the verification commands from Step 3.

### `error:1E08010C:DECODER` at "Resolve write token"

**Symptom:** the run fails at the "Resolve write token" step (or equivalent App token generation step) with:

```
error:1E08010C:DECODER routines::unsupported
```

**Fix:** the `APP_PRIVATE_KEY` secret has malformed newlines — most likely stripped when the PEM was pasted into the secret form. Re-paste the key directly from the original `.pem` file, preserving the `-----BEGIN RSA PRIVATE KEY-----` header and footer lines and all embedded newlines.

### Workflow-level vs job-level permissions confusion

**Symptom:** the job receives only `read` permissions even though `permissions: write` appears in the YAML. Operations that require write access fail with `403 Resource not accessible by integration`.

**Cause:** the `permissions:` block is declared inside `jobs.<job-id>:` rather than at the top level of the workflow file. GitHub silently ignores job-level permissions when the job calls a reusable workflow via `uses:`.

**Fix:** move the entire `permissions:` block to the workflow level — it must appear after `on:` and before `jobs:`. See the [Permissions Reference](../README.md#permissions-reference) in the main README for the exact block required by each workflow type.

---

## Step 7 — Optional configuration

### Authorized-user allowlist

By default, only commenters with an `author_association` of `OWNER`, `MEMBER`, or `COLLABORATOR` can trigger Claude via `@claude`. To restrict further to a named set of users:

```yaml
    with:
      authorized_users: 'alice,bob'   # comma-separated, case-insensitive
```

When `authorized_users` is non-empty, the association check is skipped — only the listed users can trigger Claude.

### Open `@claude` to all commenters

```yaml
    with:
      require_association: false   # default: true
```

**Caution:** this allows any GitHub user with comment access to consume your Claude quota. Combine with `authorized_users` or repo visibility controls.

### Model override

```yaml
    with:
      model: claude-opus-4-5   # default: claude-sonnet-4-5
```

Opus produces higher-quality reviews and more thorough fixes at the cost of higher token usage and slightly longer runtime. Sonnet is the recommended default.

### `max_turns` tuning

```yaml
    with:
      max_turns: '20'   # default: 15
```

Increase for large PRs or complex codebases where Claude needs more turns to fully diagnose an issue. Keep the default for most consumer repos.

---

## Where to go next

- **[Main README](../README.md)** — complete API reference, permissions table for every workflow, token selection guidance, migration notes from v1 → v2.
- **[`examples/README.md`](../examples/README.md)** — table mapping desired outcome to template file, plus the prerequisite checklist in condensed form.
- **[Milestone #9 — Consumer onboarding hardening](https://github.com/glitchwerks/github-actions/milestone/9)** — tracks known gaps in the onboarding flow; check here for work in progress.
- **[Issue tracker](https://github.com/glitchwerks/github-actions/issues)** — file new pain points encountered during setup so they can be addressed for the next consumer.
