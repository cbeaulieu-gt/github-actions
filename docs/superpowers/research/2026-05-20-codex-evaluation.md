---
title: Codex Surface Evaluation
date: 2026-05-20
epic: 273
milestone: codex-pivot
status: research-only — no recommendations
---

# Codex Surface Evaluation

> **Status:** research-only — no recommendations, no plan, no "we should…" statements.
> Every factual claim below is sourced and dated. Claims that could not be verified from public sources are prefixed with `unverified:`.

---

## 1. Executive Summary

As of May 2026, OpenAI Codex is a multi-surface coding agent product bundled into all ChatGPT subscription plans — Free, Go ($8/mo), Plus ($20/mo), Pro, Business, Edu, and Enterprise (Free and Go carry strict usage limits; not viable for sustained CI loads) — and accessible programmatically via the OpenAI Responses API. The product spans five surfaces: **Codex Cloud** (browser-based cloud execution environment), the **Codex GitHub integration** (an App-backed bot that reviews PRs and responds to `@codex` mentions), the **`openai/codex-action` GitHub Action** (a composable CI step), the **Codex CLI** (`@openai/codex` npm package, currently at v0.132.0 stable), and the **Responses API / Agents SDK** (programmatic access for orchestration). For CI automation, the two directly relevant surfaces are the GitHub Action (which installs the CLI and proxies the Responses API inside a runner) and the Responses API / Agents SDK (which provides programmatic orchestration without a GitHub-specific wrapper). The Codex Cloud and GitHub App integration are user-facing products that operate under OpenAI's own cloud infrastructure and require a ChatGPT identity login, making them suitable for developer-interactive workflows but constrained for fully headless automation that must run under a project-owned GitHub App identity.

Sources: [developers.openai.com/codex](https://developers.openai.com/codex) (fetched 2026-05-20), [openai.com/codex/](https://openai.com/codex/) (fetched 2026-05-20).

---

## 2. Official Integrations — Detailed Inventory

### 2.1 Codex Cloud

**What it is.** A browser-based cloud environment (also called "Codex web") where tasks run in isolated per-task sandboxes, each preloaded with the user's repository checkout. Codex can work on multiple tasks in parallel in the background. Users configure repository access, setup steps, and tools; Codex reads, edits, and runs code inside the sandbox, then proposes changes as pull requests.

**Maturity.** Generally available as of the 2026 Codex launch. The sandboxed cloud-task surface (this section) is included in Plus and above; Free and Go plan users have limited access to Codex Cloud tasks specifically (see subscription tiers below). Free and Go users retain access to other Codex surfaces (CLI, IDE integrations, mobile), but the cloud-task sandbox — background parallel tasks, repository checkout in an isolated container, PR proposal — requires Plus or above. "Codex" as an umbrella term covers all plans with usage limits; "Codex Cloud" (this surface) is the Plus-and-above constraint.
Source: [developers.openai.com/codex/cloud](https://developers.openai.com/codex/cloud) (fetched 2026-05-20), [openai.com/index/codex-now-generally-available/](https://openai.com/index/codex-now-generally-available/) (fetched 2026-05-20).

**How invoked.** Through the ChatGPT web interface at `chatgpt.com/codex`, or via `@codex` mentions on GitHub Issues and PRs (cloud tasks). Also invocable from the Codex CLI plugin-for-Claude-Code (`/codex:rescue`).

**Authentication.** Requires ChatGPT account sign-in (OAuth). The GitHub connector uses **short-lived, least-privilege GitHub App installation tokens** for each operation, derived from the user's connected GitHub account.
Source: [developers.openai.com/codex/enterprise/](https://developers.openai.com/codex/enterprise/) (fetched 2026-05-20).

**Subscription tiers.** Free, Go ($8/mo), Plus ($20/mo), Pro, Business, Edu, Enterprise. Free and Go tiers carry strict usage limits; limited cloud task access. Plus and above are viable for regular interactive use.
Source: [developers.openai.com/codex/pricing](https://developers.openai.com/codex/pricing) (fetched 2026-05-20).

**Sandbox model.** Each task runs in an isolated container environment. Internet access from the sandbox is admin-controlled in Enterprise (admins decide whether Codex can reach the public internet). The exact sandbox technology (container runtime, filesystem isolation) is not documented in the public developer docs.

**File-access scope.** Repository files are accessible because Codex checks out the repo into the sandbox. Users configure which repositories are allowed via the ChatGPT GitHub Connector settings.

**Persistence semantics.** Task results are surfaced as PRs or comments. Session rollout files exist but the retention policy is not documented publicly. `unverified:` whether sandbox state persists across separate task invocations or is ephemeral per task.

**Known limitations.**
- Requires ChatGPT sign-in — not compatible with API-key-only automation.
- Cloud features (GitHub review, Slack integration) are unavailable to API-key users.
- GitHub Enterprise Managed Users require org-owner installation of the Codex GitHub App before any user can connect repositories.
- New Enterprise workspace admins must complete admin setup before Codex is available to workspace members.

---

### 2.2 Codex GitHub Integration (App-backed)

**What it is.** A cloud-based GitHub integration, distinct from the Action, that connects Codex Cloud to GitHub pull requests and issues. Codex operates as a cloud service that reads the PR diff, follows repository review guidelines from `AGENTS.md`, and posts a code review directly on the PR. It also responds to `@codex` mentions in PR comments and GitHub Issues.

**Maturity.** Generally available; launched alongside Codex Cloud.
Source: [developers.openai.com/codex/integrations/github](https://developers.openai.com/codex/integrations/github) (fetched 2026-05-20).

**Installation.** Configured through `chatgpt.com/codex/settings/code-review`:
1. Connect the ChatGPT GitHub Connector to the target repository.
2. Enable the "Code review" toggle per repository.
3. Optionally enable "Automatic reviews" for all new PRs.
4. Optionally add a `Review guidelines` section to the repository's `AGENTS.md`.

For GitHub Enterprise Managed Users, an org owner must first install the Codex GitHub App at the organization level.
Source: [developers.openai.com/codex/enterprise/](https://developers.openai.com/codex/enterprise/) (fetched 2026-05-20).

**Repository permissions.** The GitHub App uses short-lived, least-privilege installation tokens. The exact permission set (read:contents, write:pull-requests, etc.) is not enumerated in the public docs. `unverified:` the exact GitHub App permission manifest.

**Events responded to.**
- Manual: `@codex review` comment on any PR.
- Automatic (when enabled): new PR opened (not updates to existing PRs — automatic reviews only fire on creation, not `synchronize` events).
- `@codex <any other text>`: starts a cloud task with the PR as context.
- `@codex` mention on a GitHub Issue: starts a cloud task.

**Known trigger reliability issue.** Issue [#13701](https://github.com/openai/codex/issues/13701) (open as of 2026-05-20) reports that `@codex` mention-triggered reviews are unreliable: some users require 3–4 `@codex` mentions over 10 minutes before the review fires. No documented workaround or confirmed fix.
Source: [github.com/openai/codex/issues/13701](https://github.com/openai/codex/issues/13701) (fetched 2026-05-20).

**Bot identity.** Codex posts reviews as `@codex` — the exact GitHub username or App display name is not specified in the public docs. `unverified:` whether posts appear as `openai-codex[bot]`, a user-OAuth identity, or a named GitHub App installation identity. Community reports indicate the identity shows as "Codex (OpenAI)" in PR review history, but this is not from official documentation.

**Subscription tiers.** Plus and above. Exact feature availability by tier (e.g., whether automatic reviews require Pro) is not distinguished in the docs; the pricing page lists cloud integrations (code review, Slack) as included in Plus.
Source: [developers.openai.com/codex/pricing](https://developers.openai.com/codex/pricing) (fetched 2026-05-20).

**Severity classification.** The GitHub integration flags only **P0 and P1** issues ("high-priority risks"). Lower-severity findings are filtered from the formal review.
Source: [developers.openai.com/codex/integrations/github](https://developers.openai.com/codex/integrations/github) (fetched 2026-05-20).

**`AGENTS.md` guidance.** Review guidelines in the repository's top-level `AGENTS.md` are applied automatically. Codex applies guidance from the `AGENTS.md` closest to each changed file (file-proximity resolution). This is the primary customization hook for review behavior.

**Post-review fix loop.** After a review, `@codex fix it` (or similar) starts a new cloud task that pushes a fix commit to the PR branch if the GitHub App has push access.

**Key limitation vs. the Action.** The GitHub App integration operates entirely within OpenAI's cloud; it cannot be configured to use a different model, a custom endpoint, a custom schema, or a different bot identity. The Action gives full control over all of these.

---

### 2.3 `openai/codex-action`

**Repository.** [github.com/openai/codex-action](https://github.com/openai/codex-action) — 1,000 stars, 122 forks as of 2026-05-20.

**Current stable tag.** `v1.8` (released 2026-04-29). The floating `v1` tag always points to the latest v1.x, currently also pinned to v1.8.
Source: [github.com/openai/codex-action/tags](https://github.com/openai/codex-action/tags) (fetched 2026-05-20).

**Version history.**

| Tag  | Release Date |
|------|-------------|
| v1.8 | 2026-04-29  |
| v1.7 | 2026-04-25  |
| v1.6 | 2026-03-17  |
| v1.5 | 2026-03-17  |
| v1.4 | 2025-11-19  |
| v1.3 | 2025-11-19  |
| v1.2 | 2025-11-07  |
| v1.1 | 2025-11-05  |
| v1.0 | 2025-10-06  |

Note: the releases tab on GitHub shows "There aren't any releases here" — versions are tracked as tags only, not GitHub Releases.
Source: [github.com/openai/codex-action/releases](https://github.com/openai/codex-action/releases) (fetched 2026-05-20).

**What it is.** A composite GitHub Action that:
1. Installs the Codex CLI (`@openai/codex`) via npm.
2. Starts an OpenAI Responses API proxy (`openai-api-key` is marked required in the inputs table below; `unverified:` whether the action falls back to subscription auth if the key is absent — the "only when provided" reading from the action README conflicts with the `(required)` annotation in `action.yml`).
3. Runs `codex exec` under the selected sandbox mode.
4. Exposes the final Codex message as a job output (`final-message`).

**Inputs (from `action.yml`).**

| Input | Description | Default |
|-------|-------------|---------|
| `prompt` | Inline prompt text | (empty) |
| `prompt-file` | Path to prompt file in repo | (empty) |
| `output-file` | File to write final Codex message | (empty) |
| `openai-api-key` | OpenAI API key | (required) |
| `responses-api-endpoint` | Custom endpoint URL (Azure OpenAI) | (empty) |
| `working-directory` | Directory for Codex operations | (empty = repo root) |
| `sandbox` | `workspace-write` / `read-only` / `danger-full-access` | `workspace-write` |
| `codex-version` | Pin specific `@openai/codex` version | (latest) |
| `codex-args` | Extra args passed to `codex exec` | (empty) |
| `output-schema` | Inline JSON Schema string | (empty) |
| `output-schema-file` | Path to JSON Schema file | (empty) |
| `model` | Model override | (Codex default) |
| `effort` | Reasoning effort level | (Codex default) |
| `codex-home` | Reuse Codex config across steps | (empty) |
| `safety-strategy` | `drop-sudo` / `unprivileged-user` / `read-only` / `unsafe` | `drop-sudo` |
| `codex-user` | UNIX username for `unprivileged-user` | (empty) |
| `allow-users` | Comma-separated GitHub users allowed to trigger | (empty) |
| `allow-bots` | Allow `github-actions[bot]` | `false` |
| `allow-bot-users` | Comma-separated trusted bot usernames | (empty) |

Source: [github.com/openai/codex-action/blob/main/action.yml](https://github.com/openai/codex-action/blob/main/action.yml) (fetched 2026-05-20).

**Outputs.**

| Output | Description |
|--------|-------------|
| `final-message` | Raw text output from `codex exec` |

**Supported event triggers.** Event-agnostic: any GitHub Actions event that allows `actions/checkout` before the step will work (`pull_request`, `push`, `workflow_run`, `issue_comment`, `workflow_dispatch`, `schedule`, etc.), **with one critical exception:** `pull_request` events from forked repositories do not receive repository secrets — `OPENAI_API_KEY` will be undefined and the action will fail authentication. Dependabot-authored PRs are treated like forks for permission hardening, so regular Actions secrets are unavailable to them as well. However, GitHub provides a separate **Dependabot secrets** namespace (Settings → Secrets and variables → Dependabot) that Dependabot-triggered workflows CAN read; if you need Codex review on Dependabot PRs specifically, configure `OPENAI_API_KEY` in that namespace in addition to regular Actions secrets. For fork-friendly review automation more broadly, use `pull_request_target` (which runs in the base-repo context with secrets available) or queue fork reviews via a separate workflow triggered against the merged base. The Codex GitHub App integration (§2.2), by contrast, runs cloud-side under OpenAI's own identity and does not have this constraint.

Source for Dependabot secrets namespace: [docs.github.com/en/code-security/dependabot/working-with-dependabot/configuring-access-to-private-registries-for-dependabot](https://docs.github.com/en/code-security/dependabot/working-with-dependabot/configuring-access-to-private-registries-for-dependabot) (fetched 2026-05-20).

> **Critical safety caveat for `pull_request_target`:** `pull_request_target` runs in the base-repo context with secrets, but the default `actions/checkout` step without arguments checks out the base ref — not the PR head. If a workflow under `pull_request_target` explicitly checks out the PR head (e.g., `with: ref: ${{ github.event.pull_request.head.sha }}`), it executes potentially-malicious code from the fork with full base-repo permissions, including secrets and write tokens. This is the well-known "pwn request" attack pattern. Mitigations:
> - Do NOT check out PR head code under `pull_request_target` unless absolutely necessary; if you must, gate on `author_association` (OWNER / MEMBER / COLLABORATOR) before any step that executes PR code.
> - Prefer a queued-review pattern where a workflow under `pull_request_target` only posts a review comment based on the diff text, not by executing PR code.
> - For `openai/codex-action` specifically: the action runs `codex exec` against the checked-out workspace — it does NOT fetch the PR diff via API. This means `pull_request_target` is NOT inherently safer here: if the workflow does not check out the PR head (the nominally safe option), Codex sees only the base branch and produces useless or empty reviews; if it does check out the PR head (`ref: ${{ github.event.pull_request.head.sha }}`), the workflow re-introduces the "pwn request" attack surface. The fork-safe pattern for `openai/codex-action` is to NOT use `pull_request_target` for fork PRs at all — instead, either restrict review to non-fork PRs (`if: github.event.pull_request.head.repo.full_name == github.repository`), or use a separate `workflow_dispatch` / scheduled reviewer that re-runs once a maintainer has triaged the fork. The Codex GitHub App is the cleanest answer if cross-fork review coverage is needed.
>
> Source: [securitylab.github.com/research/github-actions-preventing-pwn-requests/](https://securitylab.github.com/research/github-actions-preventing-pwn-requests/) (fetched 2026-05-20).

Source: [docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions](https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions) (fetched 2026-05-20).

**Sandbox modes.**

| `sandbox` value | Filesystem access |
|-----------------|------------------|
| `workspace-write` (default) | Read + write to repo files |
| `read-only` | Filesystem read-only; Codex cannot modify files |
| `danger-full-access` | Unrestricted; use with extreme care |

**`safety-strategy` options.**

| Value | Behavior |
|-------|----------|
| `drop-sudo` (default, Linux/macOS) | Revokes `sudo` membership before invoking Codex; irreversible within the job |
| `unprivileged-user` | Runs Codex as a specified non-root UNIX user |
| `read-only` | Filesystem read-only | 
| `unsafe` | No privilege reduction; required on Windows |

**Windows support.** Only `safety-strategy: unsafe` is supported on Windows runners. Standard privilege removal does not work.

**`--output-schema` support.** The `output-schema` (inline) and `output-schema-file` (path) inputs pass the schema to `codex exec --output-schema`, which enforces a JSON Schema on the final response. This is the mechanism for structured-output quality gating.

**MCP integration.** The `codex-home` input allows sharing a Codex config directory (including `config.toml` with MCP server definitions) across Action steps. The CLI uses `config.toml` (not `.mcp.json`) to configure MCP servers.

**Filesystem contract.** Codex sees the repository via the preceding `actions/checkout` step. The `output-file` input persists Codex's final message to disk for artifact collection or downstream step consumption. File writes are constrained by the `sandbox` mode.

**Authentication.** Requires `OPENAI_API_KEY` stored as a GitHub secret. Also supports Azure OpenAI via `responses-api-endpoint`. No subscription-based auth for the Action — API key is the only supported path. This is consistent with OpenAI's guidance: "Use an API key. CI, SDKs, app backends, and headless jobs need explicit platform credentials."
Source: [blog.laozhang.ai/en/posts/codex-api-key-vs-subscription](https://blog.laozhang.ai/en/posts/codex-api-key-vs-subscription) (fetched 2026-05-20).

**Node.js setup.** The action internally uses `actions/setup-node@49933ea5288caeca8642d1e84afbd3f7d6820020` (v4.4.0) pinned to a SHA for security.

**Known limitations.**
- `drop-sudo` is irreversible within a job — subsequent steps cannot use `sudo`.
- Privilege removal does not protect secrets on its own; input sanitization is still required.
- Structured output (`--output-schema`) is broken when MCP servers or tools are active — see §6 Known Constraints.
- Windows requires `unsafe` mode.
- No GitHub Releases page — only tags. Changelog is in the CLI repo, not the action repo.

---

### 2.4 Codex CLI

**Package.** `@openai/codex` on npm. Install globally: `npm i -g @openai/codex`.

**Current stable version.** `0.132.0` (released 2026-05-20). Alpha of `0.133.0` also available.
Source: [github.com/openai/codex/releases](https://github.com/openai/codex/releases) (fetched 2026-05-20).

**Language.** Built in Rust.

**Platforms.** macOS, Linux, Windows (PowerShell/WSL2).

**License.** Apache 2.0, open source.

**Key CLI command for CI — `codex exec`.**

```bash
# Non-interactive execution
codex exec "<prompt>"
codex exec --sandbox workspace-write "fix the failing tests"
codex exec --sandbox read-only --output-schema review-schema.json - < prompt.md

# Output control
codex exec --json                              # JSONL events to stdout
codex exec -o /tmp/result.txt                 # write final message to file
codex exec --output-last-message result.json  # alias for -o
codex exec --output-schema schema.json        # enforce JSON Schema on final response

# Session management
codex exec resume --last "<followup prompt>"  # continue last session
codex exec resume <SESSION_ID>                # resume by ID

# Useful flags
--ephemeral              # skip persisting session rollout files
--skip-git-repo-check    # override git repo requirement
--ignore-user-config     # don't load ~/.codex/config.toml
--ignore-rules           # skip user/project execution policy rules
```

Source: [developers.openai.com/codex/noninteractive](https://developers.openai.com/codex/noninteractive) (fetched 2026-05-20).

**JSONL event types** (with `--json`).
- `thread.started`, `turn.started`, `turn.completed`
- Item types: agent messages, reasoning, command executions, file changes, MCP calls, web searches.

**Authentication in CI.**
- `OPENAI_API_KEY=<key>` environment variable (recommended).
- Enterprise: `~/.codex/auth.json` for ChatGPT-managed auth (treated as a password; not for sharing).

**MCP configuration.** Stored in `~/.codex/config.toml` (user-level) or `.codex/config.toml` (project-level, trusted projects only). Not `.mcp.json`.

**Rapid release cadence.** The CLI ships multiple releases per week, including alpha pre-releases. Teams using the Action's auto-selected latest version should expect frequent updates. Pin `codex-version` in the Action for reproducibility.

**Known issues.**
- Token consumption loop: Issues [#16058](https://github.com/openai/codex/issues/16058) and [#19996](https://github.com/openai/codex/issues/19996) report some CLI versions consuming tokens rapidly at startup or during idle periods (one user reported ~2% of a 5-hour limit every 90 seconds; another consumed 68% of their weekly limit `cat`-ing a 350-line file). Both issues were closed as duplicates of [#14593](https://github.com/openai/codex/issues/14593). Fixed status in current stable: `unverified:`.

---

### 2.5 Responses API and Agents SDK

**Codex-specific model family.** The models available for programmatic Codex use (accessed via the Responses API) are:

| Model ID | Context Window | Max Output | Input $/1M | Cached $/1M | Output $/1M | Notes |
|----------|---------------|------------|-----------|------------|------------|-------|
| `gpt-5-codex` | 400,000 tokens | 128,000 tokens | $1.25 | $0.125 | $10.00 | Responses API only; optimized for agentic coding |
| `gpt-5.3-codex` | 400,000 tokens | 128,000 tokens | $1.75 | $0.175 | $14.00 | Optimized for agentic coding; supports multiple reasoning effort levels |
| `gpt-5.5` | 1,000,000 tokens | `unverified:` | `unverified:` (API pricing page returned 403 at write time; see [developers.openai.com/api/docs/pricing](https://developers.openai.com/api/docs/pricing), fetched 2026-05-20) | — | — | General-purpose; cookbook recommends for code review accuracy |
| `gpt-5.4` | `unverified:` | `unverified:` | 62.50 credits/1M (Business tier) | 6.25 credits/1M | 375 credits/1M | — |
| `gpt-5.4-mini` | `unverified:` | `unverified:` | 18.75 credits/1M (Business tier) | 1.875 credits/1M | 113 credits/1M | — |

Note: The Business-tier "credits" pricing uses a different denomination than the Responses API dollar pricing. The Responses API `gpt-5-codex` and `gpt-5.3-codex` prices above are in USD per 1M tokens, verified from the models documentation. Priority pricing tiers for `gpt-5.3-codex` were not confirmed on the official model page and have been removed.
Source: [developers.openai.com/api/docs/models/gpt-5-codex](https://developers.openai.com/api/docs/models/gpt-5-codex) (fetched 2026-05-20), [developers.openai.com/api/docs/models/gpt-5.3-codex](https://developers.openai.com/api/docs/models/gpt-5.3-codex) (fetched 2026-05-20), [developers.openai.com/api/docs/pricing](https://developers.openai.com/api/docs/pricing) (fetched 2026-05-20).

**Supported features.** Streaming, function calling, structured outputs (`response_format`), reasoning tokens.

**Unsupported.** Fine-tuning, predicted outputs, audio, video.

**Rate limits** (for `gpt-5-codex`).

| API Tier | RPM | TPM |
|----------|-----|-----|
| Tier 1 | 500 | 500K |
| Tier 2 | 5,000 | 1M |
| Tier 3 | 5,000 | 2M |
| Tier 4 | 10,000 | 4M |
| Tier 5 | 15,000 | 10M |

Source: [developers.openai.com/api/docs/models/gpt-5-codex](https://developers.openai.com/api/docs/models/gpt-5-codex) (fetched 2026-05-20).

**Agents SDK / `codex mcp-server`.** The Codex CLI can run as an MCP server (`codex mcp-server`), exposing two tools to an OpenAI Agents SDK orchestrator:

- `codex`: initiates a session (params: `prompt`, `approval-policy`, `sandbox`, `config`, `cwd`, `model`).
- `codex-reply`: continues an existing session (params: `prompt`, `threadId`).

Key CI parameter: `"approval-policy": "never"` eliminates interactive approval prompts.
Source: [developers.openai.com/codex/guides/agents-sdk](https://developers.openai.com/codex/guides/agents-sdk) (fetched 2026-05-20).

**SDK language support.**

| Language | Package | Maturity |
|----------|---------|----------|
| TypeScript | `@openai/codex-sdk` (npm) | Stable; Node.js 18+ required |
| Python | From local repo `sdk/python` | Experimental; Python 3.10+, requires local Codex repo checkout |

**Structured outputs via API.** The Responses API supports `response_format: { type: "json_schema", ... }` for schema-constrained JSON. This is the API-level equivalent of `--output-schema` in the CLI. The same MCP-active bug applies: `response_format.strict` may be dropped when tools are active.
Source: [developers.openai.com/api/docs/guides/structured-outputs](https://developers.openai.com/api/docs/guides/structured-outputs) (fetched 2026-05-20).

---

## 3. Third-Party Integrations

### 3.1 `openai/codex-plugin-cc` (Official)

**What it is.** An official OpenAI plugin for Claude Code that wraps the local Codex CLI as an MCP server, enabling cross-model workflows from within Claude Code.
Source: [github.com/openai/codex-plugin-cc](https://github.com/openai/codex-plugin-cc) (fetched 2026-05-20).

**Install.** `/plugin marketplace add openai/codex-plugin-cc`, then `/plugin install codex@openai-codex`.

**Commands.** `/codex:review`, `/codex:adversarial-review`, `/codex:rescue`, `/codex:status`, `/codex:result`, `/codex:cancel`.

**Architecture.** Delegates through the local Codex CLI (not a remote API call); uses the same `~/.codex/config.toml` and authentication as a direct CLI invocation.

**Authentication.** Requires Codex CLI authentication (ChatGPT account or API key). Usage counts toward Codex limits.

**Maturity.** Official OpenAI release; no version tag visible from public search. GitHub README references `claude mcp add codex-cli -- npx -y codex-mcp-server` as an alternative install path.

**Limitations.** Review can be time-consuming for multi-file changes. Review gate ("optional safety feature") may drain usage limits quickly. Requires separate Codex authentication beyond Claude Code's own session.

### 3.2 `tuannvm/codex-mcp-server` (Community)

**What it is.** Community MCP server that bridges Claude Code with the Codex CLI.
Source: [github.com/tuannvm/codex-mcp-server](https://github.com/tuannvm/codex-mcp-server) (fetched 2026-05-20).

**Quality signals.** 460 stars; latest release v1.4.10 (2026-04-10). MIT licensed.

**Install.** `claude mcp add codex-cli -- npx -y codex-mcp-server`

**Requirements.** Codex CLI v0.75.0+, OpenAI API key.

**Capabilities.** Multi-turn conversations, code analysis, AI code review for uncommitted changes or branches, web search, structured output with metadata.

**Relationship to official plugin.** Predates `openai/codex-plugin-cc`; the official plugin's alternative install path uses this same pattern. They serve overlapping purposes but are maintained independently.

### 3.3 `milanhorvatovic/codex-ai-code-review` (Community, GitHub Marketplace)

**What it is.** Third-party GitHub Marketplace action implementing a three-job PR review pipeline on top of `openai/codex-action`.
Source: [github.com/marketplace/actions/codex-ai-code-review](https://github.com/marketplace/actions/codex-ai-code-review) (fetched 2026-05-20).

**Quality signals.** 0 stars; 5 contributors (mostly automation bots); 12 open issues; current version v2.1.0. MIT licensed. Not certified by GitHub.

**Architecture.** Three jobs: `prepare` (read-only, assembles diff chunks), `review` (matrix-parallel Codex invocations per chunk), `publish` (posts inline comments via GitHub API filtered by `min-confidence`).

**Notable inputs.** `exclude-paths` (skip dist, lock files), `review-reference-file` (custom rules), `min-confidence` threshold, `max-comments` cap, `fail-on-missing-chunks`.

**Assessment.** Low quality signals (0 stars, bot-dominated contributors). Provides architectural reference for a chunked parallel review pattern; should not be used in production without evaluation.

### 3.4 `agency-ai-solutions/openai-codex-mcp` (Community)

**What it is.** Community MCP server wrapping the Codex CLI API.
Source: [github.com/agency-ai-solutions/openai-codex-mcp](https://github.com/agency-ai-solutions/openai-codex-mcp) (fetched 2026-05-20).

**Quality signals.** Not retrieved in search results. `unverified:` star count, release date, maintenance status.

### 3.5 GitHub MCP Server with Codex

The official GitHub MCP server (`github/github-mcp-server`) includes a Codex install guide, enabling Codex to interact with GitHub repositories via MCP tools within the Codex CLI.
Source: [github.com/github/github-mcp-server/blob/main/docs/installation-guides/install-codex.md](https://github.com/github/github-mcp-server/blob/main/docs/installation-guides/install-codex.md) (fetched via search 2026-05-20).

### 3.6 `hashgraph-online/awesome-codex-plugins`

A curated list of community plugins and skills for Codex; serves as a discovery index. Quality and maintenance of individual entries varies.
Source: [github.com/hashgraph-online/awesome-codex-plugins](https://github.com/hashgraph-online/awesome-codex-plugins) (fetched via search 2026-05-20).

### 3.7 Third-Party Landscape Assessment

The third-party Codex CI ecosystem is thin relative to the Claude Code ecosystem. The most relevant third-party artifact is `tuannvm/codex-mcp-server` (460 stars, active maintenance), which is the basis for the official cross-model pattern. Marketplace Actions built on Codex are nascent and low-signal (0-star counts, bot contributors). Teams building CI automation should treat third-party wrappers as architectural references rather than production dependencies at this time.

---

## 4. BKMs — Best Known Methods from Real Teams

### 4.1 PR Review Patterns

**Official cookbook pattern (GitHub Actions).**

The OpenAI cookbook's "Build Code Review with the Codex SDK" recipe (supporting GitHub Actions, GitLab CI/CD, Azure DevOps, Jenkins) uses the following approach:
Source: [developers.openai.com/cookbook/examples/codex/build_code_review_with_codex_sdk](https://developers.openai.com/cookbook/examples/codex/build_code_review_with_codex_sdk) (fetched 2026-05-20).

Workflow:
1. Install Codex CLI in the runner.
2. Build a review prompt containing: repository name, PR identifier, base/head SHAs, `git diff --name-status` (changed file list), and `git diff --unified=5` (full unified diff with 5-line context).
3. Run `codex exec --output-schema codex-output-schema.json --output-last-message codex-output.json --sandbox read-only - < codex-prompt.md`.
4. Parse the JSON output and post findings as inline PR comments via the GitHub API.

Context provision: diff-only (no entire repository is transmitted). Codex may use its own file-reading tools within the `read-only` sandbox to explore additional context if the prompt directs it to. `unverified:` whether the CLI autonomously reads non-diff files during read-only review without explicit prompt instruction.

**Structured output schema** used in the cookbook:

```json
{
  "type": "object",
  "properties": {
    "findings": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "title":            { "type": "string", "maxLength": 80 },
          "body":             { "type": "string", "minLength": 1 },
          "confidence_score": { "type": "number", "minimum": 0, "maximum": 1 },
          "priority":         { "type": "integer", "minimum": 0, "maximum": 3 },
          "code_location": {
            "type": "object",
            "properties": {
              "absolute_file_path": { "type": "string" },
              "line_range": {
                "type": "object",
                "properties": {
                  "start": { "type": "integer", "minimum": 1 },
                  "end":   { "type": "integer", "minimum": 1 }
                },
                "required": ["start", "end"]
              }
            },
            "required": ["absolute_file_path", "line_range"]
          }
        },
        "required": ["title", "body", "confidence_score", "priority", "code_location"]
      }
    },
    "overall_correctness":      { "type": "string", "enum": ["patch is correct", "patch is incorrect"] },
    "overall_explanation":      { "type": "string", "minLength": 1 },
    "overall_confidence_score": { "type": "number", "minimum": 0, "maximum": 1 }
  },
  "required": ["findings", "overall_correctness", "overall_explanation", "overall_confidence_score"]
}
```

**Priority semantics.** Priority is an integer 0–3, but the cookbook does not define what each level means semantically (e.g., 0 = critical, 3 = minor, or the reverse). The GitHub App integration separately uses "P0 and P1" labels, but that is a prose label from the cloud product, not the SDK schema.

**Blocking criteria.** The cookbook does not mandate CI failure based on schema output. The `overall_correctness` enum ("patch is correct" / "patch is incorrect") provides a binary gate, but the examples do not wire this to a workflow `exit 1`. Adding this wiring requires additional shell logic around the `final-message` output.

**Recommended model.** The cookbook recommends `gpt-5.5` for "strongest code review accuracy and consistency."

**Prompt discipline note.** The cookbook prompt explicitly instructs: "Flag only actionable issues introduced by the pull request" and requires accurate line numbers: "Ensure that file citations and line numbers are exactly correct using the tools available; if they are incorrect your comments will be rejected."

**API key isolation.** The cookbook drops `sudo` permissions before Codex execution to prevent it from reading GitHub secrets off the runner. Critical for public repositories.

### 4.2 Lint-Fix / Auto-Fix Patterns

**Official cookbook recipe (CI failure auto-fix).**
Source: [developers.openai.com/cookbook/examples/codex/autofix-github-actions](https://developers.openai.com/cookbook/examples/codex/autofix-github-actions) (fetched 2026-05-20).

Trigger: `workflow_run` on a failed "CI" workflow.

Workflow:
1. Validate `OPENAI_API_KEY` is present.
2. Check out the failing commit.
3. Install dependencies.
4. `codex exec --sandbox workspace-write "identify and fix the failure"` with a system message describing the repo tech stack and constraining scope: "implement only that change, and stop. Do not refactor unrelated code or files."
5. Re-run tests to verify the fix.
6. If tests pass, create a PR named `codex/auto-fix-{run_id}` with the changes.

Caveats:
- Specific to Node.js / Jest in the cookbook example; other tech stacks require prompt adaptation.
- Creates a PR for human inspection rather than directly committing to the original branch.
- Requires `contents: write` and `pull-requests: write` permissions.
- `unverified:` whether the pattern has a documented variant that commits directly (rather than opening a new PR).

**GitLab pattern (code quality + security, marker-based output).**
Source: [developers.openai.com/cookbook/examples/codex/secure_quality_gitlab](https://developers.openai.com/cookbook/examples/codex/secure_quality_gitlab) (fetched 2026-05-20).

Key technique for reliable structured output when `--output-schema` cannot be trusted: **strict marker-based prompts** with post-processing extraction.

```
=== BEGIN_CODE_QUALITY_JSON ===
[only JSON here]
=== END_CODE_QUALITY_JSON ===
```

The workflow then:
1. Strips ANSI escape codes with `sed`.
2. Extracts content between markers with shell.
3. Validates JSON syntax with Node.js.
4. Falls back to `[]` on invalid JSON.
5. Stores `.patch` files as artifacts; validates with `git apply --check` before storing.

This pattern is documented as a workaround for the `--output-schema` + tools conflict (issue #15451). It works regardless of whether MCP servers are active.

### 4.3 Cross-Model Review Patterns (Claude Writes / Codex Reviews)

**Official pattern.** The `openai/codex-plugin-cc` plugin enables a documented "writer-reviewer separation" pattern where Claude Code authors code and Codex provides independent review via `/codex:review` or `/codex:adversarial-review`.

Architecture: Claude Code → Codex MCP server (via `openai/codex-plugin-cc`) → local Codex CLI → OpenAI API.

The pattern is described by OpenAI as addressing "sycophancy bias" — a model reviewing its own code tends to miss the same vulnerability patterns it generates.
Source: [github.com/openai/codex-plugin-cc](https://github.com/openai/codex-plugin-cc) (fetched 2026-05-20), [mindstudio.ai/blog/openai-codex-plugin-claude-code-cross-provider-review](https://www.mindstudio.ai/blog/openai-codex-plugin-claude-code-cross-provider-review) (fetched 2026-05-20).

In a CI context, this pattern requires:
1. Claude Code (or `claude-code-action@v1`) to complete a task and produce a branch/diff.
2. A subsequent job invoking `openai/codex-action@v1.8` with a review prompt and `--output-schema`.

**Community practice.** Several teams (unnamed in public sources) report using writer-reviewer separation for security passes in CI, treating Codex review as a complement to traditional static analysis.
Source: [mindstudio.ai/blog/openai-codex-plugin-claude-code-cross-provider-review](https://www.mindstudio.ai/blog/openai-codex-plugin-claude-code-cross-provider-review) (fetched 2026-05-20).

### 4.4 Structured-Output Gating Patterns

Two patterns exist in the public record:

**Pattern A: `--output-schema` with no MCP servers.**
Use `--output-schema schema.json` in `codex exec` when the prompt does not activate any MCP servers or tools. The CLI enforces the schema on the final response. This is the path documented in the official cookbook.

**Pattern B: Marker extraction (workaround for issue #15451).**
When MCP servers or tools must be active (e.g., Codex needs to read files during review), use strict text markers in the prompt to delimit structured output and extract / validate it in a post-processing shell step. Less brittle against the `--output-schema` + tools conflict.

**Blocking gate wiring.** Neither pattern documents a canonical "fail the workflow" step. Both require the caller to parse the structured output and `exit 1` on finding `"overall_correctness": "patch is incorrect"` or a finding `priority` meeting a threshold.

### 4.5 Failure Modes and Known Footguns

| Failure Mode | Description | Source |
|-------------|-------------|--------|
| `--output-schema` + MCP/tools conflict | `--output-schema` and `--json` are silently ignored when any MCP server or tool is active, producing malformed output instead of valid JSON. Closed as a bug (issue #15451) but no fix version documented. | [github.com/openai/codex/issues/15451](https://github.com/openai/codex/issues/15451) (fetched 2026-05-20) |
| `@codex` mention trigger unreliability | The GitHub App integration does not reliably respond to `@codex` on the first mention; may require 3–4 retries over 10 minutes. | [github.com/openai/codex/issues/13701](https://github.com/openai/codex/issues/13701) (fetched 2026-05-20) |
| Token consumption loop at startup | Some CLI versions consume tokens rapidly during startup or idle (rate: ~2% of 5-hour limit per 90 seconds in extreme cases). | [github.com/openai/codex/issues/16058](https://github.com/openai/codex/issues/16058), [#19996](https://github.com/openai/codex/issues/19996) (fetched via search 2026-05-20) |
| GitHub OAuth token theft via command injection | Malicious branch names with Unicode spaces could inject shell commands during `git clone`, stealing the GitHub OAuth token. Reported December 2025, initial hotfix December 23, full remediation February 5, 2026. | [beyondtrust.com/blog/entry/openai-codex-command-injection-vulnerability-github-token](https://www.beyondtrust.com/blog/entry/openai-codex-command-injection-vulnerability-github-token) (fetched 2026-05-20) |
| `drop-sudo` breaking later steps | `drop-sudo` is irreversible within a job. Downstream steps requiring `sudo` fail. Documented workaround: separate jobs on fresh runners. | [github.com/openai/codex-action](https://github.com/openai/codex-action) README (fetched 2026-05-20) |
| Automatic reviews on creation only | GitHub App integration auto-reviews fire on PR creation, not on `synchronize` (new commits). Re-review on updates requires a manual `@codex review` comment. | [developers.openai.com/codex/integrations/github](https://developers.openai.com/codex/integrations/github) (fetched 2026-05-20) |
| Line number accuracy in comments | Codex sometimes produces incorrect file paths or line numbers in inline comments; GitHub rejects anchors that don't match the diff. Requires prompt reinforcement. | [developers.openai.com/cookbook/examples/codex/build_code_review_with_codex_sdk](https://developers.openai.com/cookbook/examples/codex/build_code_review_with_codex_sdk) (fetched 2026-05-20) |
| April 9 limit model change | Limits shifted from message-count to reasoning-time measurement. `unverified — community estimate:` budgets burn up to 3.2× faster per minute on Business tier; primary OpenAI documentation confirming the multiplier was not located. Iterative CI workflows are disproportionately affected. | [community.openai.com/t/understanding-the-new-codex-limit-system-after-the-april-9-update/1378768](https://community.openai.com/t/understanding-the-new-codex-limit-system-after-the-april-9-update/1378768) (fetched 2026-05-20) |
| Business tier limit regression | `unverified — community estimate:` Business tier Codex limits regressed significantly in the April 9 update; community reports of users canceling due to "unmanageable" usage. No primary OpenAI changelog or blog post confirming the specific regression magnitude was located. | Same source as above. |
| Azure DevOps inline comment anchoring | `changeTrackingId` mapping is fragile; inline comments may fail silently. Must be validated per project before relying on in a required branch policy. | [developers.openai.com/cookbook/examples/codex/build_code_review_with_codex_sdk](https://developers.openai.com/cookbook/examples/codex/build_code_review_with_codex_sdk) (fetched 2026-05-20) |
| API key auth and ChatGPT-plan auth are per-session, not mutually exclusive | API-key and ChatGPT-plan auth are **switchable modes** rather than a one-way exclusion. In any single CLI session only one auth mode is active (run `codex logout` then re-authenticate). During an API-key session, features that depend on the ChatGPT cloud surface (GitHub App integration, Slack integration, cloud-feature rollout priority) are unavailable, but the same account can switch back to ChatGPT-plan auth for interactive use. Practical implication: use API-key auth for headless CI; ChatGPT-plan auth for interactive terminal/IDE use on the same account. `unverified:` the third-party source below claims "disables" these features permanently — official OpenAI docs describe switchable modes, making the permanent-exclusion framing inaccurate. | `unverified — third-party source:` [blog.laozhang.ai/en/posts/codex-api-key-vs-subscription](https://blog.laozhang.ai/en/posts/codex-api-key-vs-subscription) (fetched 2026-05-20); switchable-mode behavior per OpenAI CLI documentation |

**Harness engineering case study.** OpenAI published a case study about an internal team that built an entire software project using Codex. `unverified:` figures extracted from search snippets only — primary article returned 403 on direct fetch at write time, so the following metrics may be incomplete or imprecise: approximately 1,500 PRs over 5 months with a 3–7 person team. The key patterns described in snippets: every PR had CI, every CI run was reviewed by Codex, and scope was tightly bounded ("do not refactor unrelated code"). These figures are not confirmed from the primary source.
Source: [openai.com/index/harness-engineering/](https://openai.com/index/harness-engineering/) (search-retrieved 2026-05-20; direct fetch returned 403).

---

## 5. Capabilities Mapped to Core Requirements

### 5.1 Capability Matrix

| Requirement | Codex Cloud (App) | GitHub App Integration | `codex-action` (Action) | Codex CLI (headless) | Responses API |
|-------------|------------------|----------------------|------------------------|---------------------|---------------|
| Context-aware reviewing (diff + non-diff context) | `?` unverified — cloud sandbox has full repo checkout | `partial` — diff reviewed; AGENTS.md guidance; `unverified:` whether Codex reads non-diff files autonomously | `✓ verified` — `read-only` sandbox + full repo checkout; Codex uses file-read tools during review | `✓ verified` — `read-only` sandbox + full repo checkout; same CLI behavior | `✓ verified` — caller passes diff and can append any additional context to the prompt |
| Structured-output quality gate (severity enum, finding counts, blocking/non-blocking) | `✗ confirmed unavailable` — no schema output from cloud App | `✗ confirmed unavailable` — P0/P1 labels only; no machine-parseable schema | `partial` — `output-schema` / `output-schema-file` inputs exist; broken when MCP/tools active (issue #15451) | `partial` — `--output-schema` flag exists; same bug when tools active; marker-extraction workaround available | `✓ verified` — `response_format: json_schema` with `strict: true`; same tool-active limitation applies |
| PR review flow | `✓ verified` — automatic or `@codex review` triggered | `✓ verified` — manual or automatic; fires on creation only | `✓ verified` — invoke on `pull_request` events; full control | `✓ verified` — invoke in any CI step | `✓ verified` — call from any CI step with diff payload |
| Lint-failure diagnose/fix | `partial` — cloud task support; UX not CI-friendly | `partial` — `@codex` mention on issue/PR; trigger unreliable | `✓ verified` — `workspace-write` sandbox; official cookbook recipe | `✓ verified` — official cookbook recipe | `✓ verified` |
| CI-failure diagnose/fix | `partial` — cloud task; requires GitHub issue trigger | `partial` — same as above | `✓ verified` — `workflow_run` trigger on failure; official cookbook recipe | `✓ verified` | `✓ verified` |
| Manual apply-fix | `✓ verified` — interactive cloud task | `✓ verified` — `@codex fix it` on PR | `✓ verified` — `workflow_dispatch` trigger | `✓ verified` — invoke in `workflow_dispatch` job | `✓ verified` |
| `@mention` verb router | `partial` — `@codex` on issues/PRs; no verb routing, any non-`review` text starts a cloud task | `✓ verified` — `@codex review` / `@codex fix it` / `@codex <anything>` | `partial` — Action is event-agnostic; verb parsing must be implemented by the caller workflow (shell or composite action); no built-in verb routing | `partial` — same; no built-in verb routing | `✗ confirmed unavailable` — no GitHub event awareness |
| Auth/identity on GitHub (existing App ID / APP_PRIVATE_KEY) | `✗` — uses ChatGPT OAuth, not an App token | `✗` — uses OpenAI's own GitHub App; cannot be replaced with a custom App identity | `partial` — Action posts as `github-actions[bot]` (the runner token) unless the workflow uses a separate GitHub App token for posting; Codex itself uses the API key, not a GitHub identity | `partial` — same | `✗` — no GitHub identity; API caller must post any GitHub comments separately |
| Cost model (subscription coverage) | `✓ verified` — included in Plus+ subscription; draws from subscription budget | `✓ verified` — included in Plus+ subscription | `partial` — requires API key; subscription credits do NOT apply to Action runs; API billing only | `partial` — same; API key required | `partial` — API billing only |

### 5.2 Requirement Notes

**Context-aware reviewing.** With the Action and CLI, Codex runs inside a `read-only` sandbox on the runner where `actions/checkout` has already populated the full repository. The review prompt can include the diff explicitly, and Codex's internal file-read tools (activated automatically during an agentic session) allow it to explore related files without the caller needing to enumerate them. This satisfies "diff + relevant non-diff context" at the level of what Codex chooses to read; the caller does not need to pre-identify related files. The official cookbook recipe feeds only the diff explicitly but notes that the `read-only` sandbox permits Codex's own file tools. The GitHub App integration's sandbox is on OpenAI's cloud infrastructure; whether it can access the full repo tree or only the diff payload is `unverified:` from public docs.

**Structured-output quality gate.** The `output-schema` / `output-schema-file` inputs to `openai/codex-action@v1.8` provide a direct path to machine-parseable schema output. The official cookbook defines a schema with `priority` (0–3 integer) and `overall_correctness` (enum). This satisfies the requirement for a severity enum and machine-parseable output. However, the tool-active bug (issue #15451) means this path is unreliable when the review session uses any MCP server or tool. The marker-extraction workaround is documented and functional. The severity/blocking threshold must be implemented by the caller (e.g., `exit 1` if any finding has `priority == 0`); neither the Action nor the CLI enforces a blocking threshold automatically.

**Auth/identity.** The Action runs `codex exec` using an OpenAI API key for the model calls. GitHub interactions (posting comments, updating PR status) are performed by separate steps using `actions/github-script` or the `gh` CLI, authenticated with the runner's `GITHUB_TOKEN` or a custom App token. Codex itself does not post to GitHub — the caller workflow does. This means the existing `APP_ID` / `APP_PRIVATE_KEY` GitHub App can still be used for all write operations (comments, commits, push); Codex's identity on GitHub is controlled entirely by the workflow author, not by OpenAI.

**`@mention` verb routing.** The GitHub App integration provides native `@codex <verb>` support, but the bot identity and behavior are controlled by OpenAI. For a custom verb router (equivalent to the existing `claude-command-router/`), the Action is the correct surface: the caller implements verb parsing in the workflow, then invokes the Action with a verb-specific prompt. The Action itself has no verb-routing logic.

---

## 6. Known Constraints, Costs, and Gotchas

### 6.1 Subscription Tier Matrix

| Surface | Free | Go ($8) | Plus ($20) | Pro (`unverified:` $100/mo; internal rate-limit tiers within Pro are not exposed as distinct plan names in the pricing docs) | Business (PAYG) | Enterprise |
|---------|------|---------|-----------|-----------|----------------|------------|
| Codex Cloud (web tasks) | Limited | `unverified:` | Included | Included | Included | Included (admin setup required) |
| GitHub App integration | `unverified:` | `unverified:` | Included | Included | Included | Included |
| Codex CLI (ChatGPT auth) | Limited | `unverified:` | Included | Included | Included | Included |
| Codex CLI (API key) | API billing only (no subscription) | API billing only | API billing only | API billing only | API billing only | API billing only |
| `openai/codex-action` | API billing only | API billing only | API billing only | API billing only | API billing only | API billing only |
| Responses API | API billing only | API billing only | API billing only | API billing only | API billing only | API billing only |

Key principle: **subscription credits do not apply to CI automation** (Action or headless CLI with API key). CI usage is billed at API rates regardless of subscription tier.
Source: [developers.openai.com/codex/pricing](https://developers.openai.com/codex/pricing) (fetched 2026-05-20), [blog.laozhang.ai/en/posts/codex-api-key-vs-subscription](https://blog.laozhang.ai/en/posts/codex-api-key-vs-subscription) (fetched 2026-05-20).

If the user holds a Codex (Pro or Plus) subscription: that subscription covers interactive Codex use (cloud tasks, CLI with ChatGPT auth, GitHub App integration). It does **not** cover `openai/codex-action` runs or direct Responses API calls in CI — those require a separate API key and are billed per token.

### 6.2 Per-Token Pricing (Responses API)

| Model | Input $/1M | Cached Input $/1M | Output $/1M | Context Window |
|-------|-----------|------------------|------------|---------------|
| `gpt-5-codex` | $1.25 | $0.125 | $10.00 | 400K tokens |
| `gpt-5.3-codex` (standard) | $1.75 | $0.175 | $14.00 | `unverified:` |
| `gpt-5.3-codex` (priority) | $3.50 | $0.35 | $28.00 | `unverified:` |
| `gpt-5.5` | `unverified:` (Business: 125 credits/1M) | `unverified:` (Business: 12.50 credits/1M) | `unverified:` (Business: 750 credits/1M) | 1,000,000 tokens |
| `gpt-5.4` | `unverified:` (Business: 62.50 credits/1M) | `unverified:` (Business: 6.25 credits/1M) | `unverified:` (Business: 375 credits/1M) | `unverified:` |
| `gpt-5.4-mini` | `unverified:` (Business: 18.75 credits/1M) | `unverified:` (Business: 1.875 credits/1M) | `unverified:` (Business: 113 credits/1M) | `unverified:` |

Source: [developers.openai.com/api/docs/models/gpt-5-codex](https://developers.openai.com/api/docs/models/gpt-5-codex) (fetched 2026-05-20), [developers.openai.com/api/docs/pricing](https://developers.openai.com/api/docs/pricing) (fetched 2026-05-20).

Note: The "credits/1M" Business-tier figures from the Codex pricing page use a proprietary credit denomination, not USD. The direct-USD API pricing for `gpt-5-codex` is confirmed from the models doc; Business-tier credit rates for other models are included for reference but their USD equivalents are not confirmed.

**Rough cost estimate for a PR review.** A typical PR diff (5K tokens input, 2K tokens output) with `gpt-5-codex` costs approximately $0.006 input + $0.02 output = ~$0.026 per review. A large diff (50K tokens input, 2K tokens output) costs $0.0625 input + $0.020 output = ~$0.08 per review. These are estimates; actual costs depend on how many non-diff files Codex reads during review.

Community estimate: average ~$100–200/developer/month for full interactive use. CI-specific cost will be lower but depends heavily on diff size and review frequency.
Source: [developers.openai.com/codex/pricing](https://developers.openai.com/codex/pricing) (fetched 2026-05-20).

### 6.3 Context Window and Output Limits

- `gpt-5-codex`: 400K token context window, 128K max output tokens. Sufficient for very large diffs.
- `gpt-5.5`: 1M token context window. Useful for whole-repo analysis tasks.
- The Action does not impose additional token limits beyond the model's own limits.

### 6.4 Rate Limits Relevant to CI Burst Patterns

For `gpt-5-codex` at Tier 1 (default new API accounts): 500 RPM, 500K TPM. For a team running 50 concurrent PRs each triggering a review simultaneously, each review using a single API call, Tier 1 is adequate on RPM alone — but the 500K TPM ceiling is the binding constraint for full-context diffs: at 50K tokens/review, 50 simultaneous reviews would require 2.5M tokens, ~5× the TPM limit, throttling effective burst concurrency to roughly 10 reviews at a time.

For sustained burst patterns (e.g., a merge queue processing 100+ PRs at once), the TPM math does not support Tier 2: 100 PRs × 50K tokens/review = 5M tokens required, which exceeds Tier 2's 1M TPM ceiling by 5×, Tier 3's 2M TPM by 2.5×, and Tier 4's 4M TPM by 1.25×. The first standard tier that accommodates a 100-PR burst without throttling is **Tier 5 (15,000 RPM, 10M TPM)**. If Tier 5 is not available (it requires substantial API spend history), the realistic alternatives are: (a) rate-limit ingress so no more than ~20 reviews fire simultaneously (Tier 2 headroom), or (b) batch reviews with a queue that respects the active tier's TPM ceiling. There is no standard tier between Tier 4 and Tier 5 that covers the full 5M TPM requirement.

Rate limit tiers are determined by API usage history and spend, not by subscription. New API accounts start at Tier 1.
Source: [developers.openai.com/api/docs/models/gpt-5-codex](https://developers.openai.com/api/docs/models/gpt-5-codex) (fetched 2026-05-20).

### 6.5 Identity / Bot Login

**Action runs.** When the `openai/codex-action` workflow posts a PR comment or review via `actions/github-script`, the identity is determined by the token used by that step — either `GITHUB_TOKEN` (posts as `github-actions[bot]`) or a GitHub App installation token (posts as `<app-name>[bot]`). The existing `APP_ID` / `APP_PRIVATE_KEY` GitHub App setup used by `glitchwerks/github-actions` can be reused without modification for all write operations.

**GitHub App integration (cloud product).** Posts reviews as `@codex`. The exact GitHub app installation identity (display name, username suffix) is `unverified:` from official docs. Community observations suggest it displays as "Codex (OpenAI)" or similar but this is not confirmed from a primary source.

**Security note.** The December 2025 command-injection vulnerability (fully remediated February 5, 2026) allowed GitHub OAuth token theft via malicious branch names. The remediation involved stronger shell command protections, improved input validation, and reduced scope and lifetime of GitHub tokens in Codex containers. Teams should ensure Codex CLI is at a version post-remediation (any version current as of February 2026 or later).
Source: [beyondtrust.com/blog/entry/openai-codex-command-injection-vulnerability-github-token](https://www.beyondtrust.com/blog/entry/openai-codex-command-injection-vulnerability-github-token) (fetched 2026-05-20).

### 6.6 OAuth / Token Rotation Semantics

**API key (CI path).** Standard OpenAI API key; no automatic rotation. Must be stored as a GitHub Actions secret and rotated manually. The existing pattern of `APP_ID` / `APP_PRIVATE_KEY` for GitHub write operations is entirely separate from the OpenAI API key for model inference.

**ChatGPT OAuth tokens (interactive path).** Short-lived; automatically refreshed during active sessions. Suitable for interactive use, not for CI automation.

**Enterprise Codex access tokens.** Supported for non-interactive `codex exec` jobs in Business and Enterprise workspaces. Expiration configurable from 1 day to indefinite. Rotation process: generate replacement → update in CI secret → smoke test → revoke old token.
Source: [developers.openai.com/codex/enterprise/access-tokens](https://developers.openai.com/codex/enterprise/access-tokens) (fetched 2026-05-20).

### 6.7 Additional Gotchas

- **Deprecated `--full-auto` flag.** Replaced by explicit `--sandbox workspace-write`. Any existing scripts using `--full-auto` must be updated.
- **`required` MCP servers.** If an MCP server is declared as `required` in `config.toml` and fails to initialize, `codex exec` exits with an error rather than degrading gracefully.
- **`max_turns` cap (Agents SDK).** The MCP server runner supports a `max_turns` parameter; without it, agentic loops may run indefinitely.
- **`codex exec` and git requirement.** By default, `codex exec` requires a git repository. Override with `--skip-git-repo-check` if running outside a repo root.
- **Python SDK experimental.** The Python SDK requires a local checkout of the Codex open-source repo and is marked experimental. Not suitable for production CI pipelines without additional vetting.

---

## 7. Gaps and Open Questions

Each item below is specific enough that a 30-minute spike against a throwaway PR could resolve it.

1. **`--output-schema` + tools bug (issue #15451) — fix version.** The issue was closed on GitHub but the specific CLI version in which it was fixed is not documented in search results. Spike: install the current stable `@openai/codex@0.132.0`, run `codex exec --output-schema schema.json -c mcp_servers.test.command="echo" "return {status:'ok'}"`, observe whether output is valid JSON. Compare against the marker-extraction workaround.

2. **Exact GitHub App bot identity.** Official docs do not specify the GitHub username or App display name that Codex posts as when using the GitHub App integration. Spike: install the Codex GitHub App on a throwaway repo, trigger `@codex review`, and inspect the author identity on the resulting PR review object (`GET /repos/.../pulls/.../reviews`).

3. **GitHub App permission manifest.** The exact `contents`, `pull-requests`, `metadata` and other permission scopes required by the ChatGPT GitHub Connector App are not published. Spike: check [github.com/apps/chatgpt](https://github.com/apps/chatgpt) installation page for the declared permissions.

4. **Codex Cloud sandbox access scope.** Whether Codex Cloud tasks can access non-diff files (i.e., does the sandbox have a full repo checkout or only the diff payload) is not specified in public docs. This is critical for context-aware reviewing via the cloud product. Spike: submit a cloud task asking Codex to list files in `src/` while triggering from a PR that only touches `README.md`; observe whether it can enumerate `src/`.

5. **Automatic review on `synchronize` events.** The GitHub App integration documentation states automatic reviews fire on PR creation only. Whether a `synchronize` event can be configured to trigger automatic reviews (e.g., via webhook settings) is not confirmed. Spike: push a new commit to an open PR with automatic reviews enabled; observe whether a new review is posted.

6. **`gpt-5.5` USD pricing.** The Responses API pricing for `gpt-5.5` is published in the Business-tier "credits" denomination but not in direct USD per-token. Spike: check [platform.openai.com/docs/pricing](https://platform.openai.com/docs/pricing) for the current `gpt-5.5` USD rate.

7. **Context window for `gpt-5.3-codex`.** The model docs page for `gpt-5-codex` was confirmed (400K tokens), but `gpt-5.3-codex` context window is unverified. Spike: check [developers.openai.com/api/docs/models/gpt-5.3-codex](https://developers.openai.com/api/docs/models/gpt-5.3-codex).

8. **Enterprise access token support for `openai/codex-action`.** Enterprise Codex access tokens are documented for `codex exec` in non-interactive workflows. Whether they can be used as the `openai-api-key` input in `openai/codex-action@v1.8`, or whether a standard API key is strictly required, is not confirmed. Spike: check the Action's `action.yml` comments for the `openai-api-key` input description, and test with an enterprise access token if available.

9. **Token consumption loop status in v0.132.0.** Issues #16058 and #19996 report runaway token consumption in earlier CLI versions. Whether these are resolved in the current stable `0.132.0` is unverified. Spike: monitor token usage during a 30-minute idle `codex exec` session with `--json` logging; check for unexpected `turn.started` events.

10. **Priority semantics in the structured output schema.** The cookbook schema defines `priority` as an integer 0–3 but provides no semantic mapping (is 0 critical or trivial?). This matters for wiring a blocking gate. Spike: compare the cookbook prompt text for any inline priority definition, and run a review on a known P0 issue (e.g., a hardcoded credential) to observe what priority value is emitted.

11. **`@codex` mention on Issue creation.** Issue [#6130](https://github.com/openai/codex/issues/6130) asks whether `@codex` in the original issue body (not a comment) triggers a task. The behavior at the first comment vs. subsequent comments is reportedly different. Spike: open a new issue with `@codex investigate this bug` in the body; observe whether a cloud task is started.

12. **Subscription usage counting for `codex mcp-server` (Agents SDK path).** When Codex is run as an MCP server orchestrated by the Agents SDK, whether usage counts against a ChatGPT subscription or requires an API key is not confirmed. Spike: run a `codex mcp-server` session with ChatGPT auth and observe whether the session deducts from the subscription's 5-hour window.

---

*Document prepared 2026-05-20 as Phase 0 research for epic #273 (codex-pivot). All claims are sourced or marked `unverified:`. This document is descriptive research only — it contains no recommendations, no plan, and no prescriptive statements about what the project should do.*
