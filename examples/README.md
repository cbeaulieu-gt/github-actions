# Examples

Drop-in caller workflows for `glitchwerks/github-actions` reusable workflows. Copy any of these to your repo's `.github/workflows/` directory, then customize.

## Workflow index

| File | Reusable workflow | Trigger | Secrets required |
|---|---|---|---|
| `claude-pr-review.yml` | `claude-pr-review.yml@v2` | `pull_request` (opened/synchronize/reopened/ready_for_review) | `CLAUDE_CODE_OAUTH_TOKEN` |
| `claude-tag-respond.yml` | `claude-tag-respond.yml@v2` | `issue_comment`, `pull_request_review_comment` (created) | `CLAUDE_CODE_OAUTH_TOKEN`, `APP_ID`, `APP_PRIVATE_KEY` |
| `claude-lint-failure.yml` | `claude-lint-failure.yml@v2` | `pull_request` — fires `notify-claude` job when `lint` fails | `CLAUDE_CODE_OAUTH_TOKEN`, `APP_ID`, `APP_PRIVATE_KEY` |
| `claude-ci-failure.yml` | `claude-ci-failure.yml@v2` | `workflow_run` on completion of a named CI workflow | `CLAUDE_CODE_OAUTH_TOKEN`, `APP_ID`, `APP_PRIVATE_KEY` |
| `claude-apply-fix.yml` | `claude-apply-fix.yml@v2` | `workflow_dispatch` (manual, three inputs) | `APP_ID`, `APP_PRIVATE_KEY` |

## Before you start

Three prerequisites must be in place before any of these examples will work:

**(a) GitHub App installed on the consumer repo**

Create (or reuse) a GitHub App with the following permissions:

- Repository → Contents: Read and write
- Repository → Pull requests: Read and write

Install the App on the consumer repo and note its **App ID** and **private key (PEM)**.

**(b) Secrets available as repo or org secrets**

| Secret name | Used by |
|---|---|
| `CLAUDE_CODE_OAUTH_TOKEN` | All workflows (PR review, tag respond, lint failure, CI failure) |
| `APP_ID` | Write-path workflows: tag respond, lint failure, CI failure, apply fix |
| `APP_PRIVATE_KEY` | Same as above |

Add these under **Settings → Secrets and variables → Actions** in the consumer repo, or at the org level if you want to share them across multiple repos.

**(c) GHCR overlay packages accessible**

All five Phase 5 reusable workflows pull a container image from `ghcr.io/glitchwerks/` before running. The runner authenticates the pull with `GITHUB_TOKEN`, so the packages must be reachable:

- **Intra-`glitchwerks`-org repos:** set package visibility to **Internal** — all org repos get access automatically, no per-repo grant needed.
- **External repos:** use the package settings page to add the consumer repo with role **Read** for each of the three packages (`claude-runtime-review`, `claude-runtime-fix`, `claude-runtime-explain`).

In both cases, the caller workflow **must** declare `packages: read` at the workflow level (all five examples already do this). See the main README's [GHCR package access](../README.md#ghcr-package-access-for-org-wide-consumers) section for full instructions.

## Full reference

See the main [`README.md`](../README.md) for the complete API reference, permissions tables, token selection guidance, and troubleshooting notes.
