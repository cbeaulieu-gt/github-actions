# AGENTS.md

Project-level instructions for OpenAI Codex when reviewing pull requests in
`glitchwerks/github-actions` and consumer repos that mirror these rules.

## Project context

`glitchwerks/github-actions` is a shared GitHub Actions library that ships
reusable Claude-powered CI automation. Every capability exists in two forms: a
reusable workflow (`.github/workflows/claude-*.yml`) that external consumers
call with a single `uses:` line, and a composite action (`<name>/action.yml`)
that the reusable workflow delegates to. Logic lives in the composite action;
the reusable workflow provides the trigger context, permissions, and concurrency
block. Consumers are other `glitchwerks`-org repositories that pull the
overlay container images from GHCR and call these workflows from their own
`.github/workflows/` files. Changes to this repo therefore affect every
downstream consumer on the next release tag — correctness and security bugs
cannot be patched in consumer repos; they must be fixed here.

## Review guidelines

### Permissions

Flag any `permissions:` block placed inside `jobs.<job-id>:` rather than at
the workflow level as a P0 issue. GitHub silently ignores job-level permissions
when a job calls a reusable workflow via `uses:` — the token receives only the
default read-only scopes regardless of what the job block declares. All
`permissions:` entries must appear at the top-level workflow scope (after `on:`
and before `jobs:`). Source: `CLAUDE.md` "Key conventions".

Flag any workflow whose `jobs.<job-id>.container:` field references a
`ghcr.io/` image but whose workflow-level `permissions:` block does not include
`packages: read` as a P0 issue. Without this scope the runner's implicit
`docker pull` before the job starts returns `manifest unknown` — an
authorization-masked error that looks like the image does not exist. This has
silently broken five container-pinned workflows at once (issue #192). Source:
`CLAUDE.md` "Key conventions".

Flag any `run:` step in a composite action that tests a boolean-typed input
with `== true` (e.g. `if [[ "$VAR" == true ]]`) rather than `[ "$VAR" = "true" ]`
as a P1 issue. Composite action inputs have no `type:` field — every input
arrives as a string. The string `'true'` is not the boolean `true`; a `[[`
comparison against the unquoted literal `true` may silently pass or silently
fail depending on shell quoting. Source: `CLAUDE.md` "Key conventions".

Flag any composite action step that uses `exit 0` to prevent subsequent steps
from running as a P0 issue. `exit 0` inside a step terminates that step
successfully but does not suppress the steps that follow it. Authorization
logic must emit a step output (`echo "authorized=false" >> "$GITHUB_OUTPUT"`)
and every downstream step must gate on `if: steps.<id>.outputs.authorized == 'true'`.
Source: `CLAUDE.md` "Key conventions".

### Token and identity

Flag any `claude-code-action` invocation where `github_token` is set to
`${{ github.token }}` (the default `GITHUB_TOKEN`) rather than to a resolved
GitHub App token as a P1 issue. GitHub suppresses `synchronize` events for
commits pushed with `GITHUB_TOKEN`, breaking downstream re-trigger chains.
All Claude-powered workflows must use a short-lived App token (e.g.
`${{ steps.token.outputs.value }}`) for a consistent bot identity and correct
event propagation. Source: `CLAUDE.md` "Key conventions", issue #250.

Flag any workflow that passes `APP_PRIVATE_KEY` or a PEM-format key value
directly into a `run:` block via `env:` without using a dedicated App-token
generation action (e.g. `actions/create-github-app-token`) as a P0 issue.
Raw PEM handling in shell is error-prone and risks key material appearing in
logs.

### Shell discipline in `run:` blocks

Flag any `run:` block that contains a `${{ }}` expression literal inside a
single-quoted string without a `# shellcheck disable=SC2016` comment on the
block as a P1 issue. Shellcheck flags these as unintended non-expansion;
GitHub Actions pre-processes the expression before the shell sees the string,
so the disable comment is required to keep lint clean. Source: `CLAUDE.md`
"Key conventions".

Flag any `run:` block that uses `jq` as a standalone command (e.g. `| jq '...'`)
as a P1 issue. The CI container image does not install a standalone `jq`
binary. Use `gh --jq '<expr>'` for output from `gh` commands, or pipe through
`python -c 'import json,sys; ...'` for other JSON sources.

Flag any polling loop in a `run:` block that uses `until <check>; do sleep N; done`
or `while` without an iteration counter and `exit 1` on cap-exceeded as a P1
issue. Uncapped loops spin indefinitely when the check command errors on every
iteration, producing silent runaway background shells.

### Action reference integrity

Flag any composite `action.yml` or reusable workflow that references another
composite action via a relative `./` path (e.g. `uses: ./apply-fix`) as a P0
issue. Relative paths break for external consumers because `actions/checkout`
replaces the runner workspace with the consumer's repo — `./apply-fix` then
resolves into the consumer's repo tree, not this library. All cross-action
references must use absolute refs: `uses: glitchwerks/github-actions/<action>@<tag-or-sha>`.
Source: `CLAUDE.md` "Architecture".

Flag any third-party action reference that pins to a mutable tag (e.g.
`actions/checkout@v4`) rather than a SHA digest (e.g.
`actions/checkout@b4ffde65f46336ab88eb53be808477a3936bae11`) as a P1 issue.
Mutable tags can be silently moved to a different commit; SHA pins are
content-addressed and cannot be redirected. Exception: first-party
`actions/*` at major-version tags are acceptable but SHA-pinning is preferred.

Flag any `uses:` value that contains a GitHub Actions expression
(`${{ }}`) as a P0 issue. GitHub Actions does not evaluate expressions in
`uses:` fields — the literal string, including the `${{ }}` syntax, is passed
to the action resolver, which will fail to find the reference.

### Security

Flag any `run:` block that interpolates an untrusted value — for example a PR
title, PR body, issue comment body, or any `github.event.*` field that a
contributor controls — directly into a shell variable assignment or command
string as a P0 issue. These fields may contain shell metacharacters or
attacker-controlled content. Pass them through environment variables (`env:`
at the step level) and reference them as `$VAR` rather than as inline
expressions.

Flag any `run:` block that echoes a secret value to stdout (e.g.
`echo "${{ secrets.FOO }}"`) as a P0 issue. Use `::add-mask::` if a derived
value must be surfaced; never log the raw secret.

Flag any composite action or reusable workflow that processes arbitrary diffs
or patches without first validating that the patch does not touch protected
paths (`.github/**`) as a P0 issue. The `apply-fix` action is the reference
implementation of this check.

### GitHub Actions conventions

Flag any new required-on-merge status check added without a corresponding
ruleset entry on `main` as a P1 issue. A passing check that is not in a branch
protection ruleset can be bypassed at merge time. Every workflow that introduces
a new blocking status check must also update the ruleset. Source: `CLAUDE.md`
"Branch Protection / Rulesets".

Flag any workflow that triggers on both `push` and `pull_request` for the same
branches without a `concurrency:` group as a P1 issue. Without concurrency
control, every PR push produces two parallel runs, doubling cost and producing
duplicate review comments.

Flag any `workflow_call` reusable workflow that does not forward secrets
explicitly (`secrets: inherit` or named `secrets:` block) to nested composite
actions that require them as a P1 issue. Missing secret forwarding causes
silent empty-string values — the composite action receives `''` with no error.

### Container runtime

Flag any Dockerfile or build script that adds a `git config --config-file`
directive that shadows `/etc/gitconfig` without also preserving the
`safe.directory = *` exemption as a P0 issue. The base image bakes this
exemption into `/etc/gitconfig` to prevent `detected dubious ownership` errors
when the Actions runner mounts the workspace under a different UID. Shadowing
the file removes the exemption for all overlays that build FROM the base.
Source: `CLAUDE.md` "Container git safety (post-#199)".

Flag any change to `runtime/ci-manifest.yaml` that bumps `sources.private.ref`
to a value that does not match `^ci-v\d+\.\d+\.\d+$` as a P0 issue. The
manifest schema enforces this pattern; a free-form string will fail STAGE 1
validation and block the build.

Flag any `runtime/ci-manifest.yaml` change that bumps `sources.private.ref`
without a documented review of the `git diff` between the old and new tag as
a P1 issue. Automated bumps that skip the diff review defeat the purpose of
the pin.

### Test coverage

Flag any new composite action step that performs non-trivial conditional
logic (branching on inputs, environment variables, or API responses) without a
corresponding entry in `tests/cases.json` or an equivalent test corpus as a
P1 issue. The `claude-command-router` action and its `lib/parse.sh` function
demonstrate the expected pattern: pure logic is extracted into a sourceable
script and exercised by a JSON test corpus on every PR.

Flag any PR that modifies `lib/severity-regex.sh` without updating every
callsite that sources it (`pr-review/action.yml` quality gate, synthesis step,
and shadow gate step) as a P0 issue. The three callsites must stay in sync;
a regex update that diverges between the authoritative gate and the shadow gate
produces silent disagreement in the structured marker, masking real blockers.

## Out of scope for review

Do not flag the following; raising them adds noise without actionable signal:

- Subjective phrasing choices in documentation prose (word order, synonym
  selection, paragraph structure).
- Stylistic formatting in Markdown files where no project convention exists
  (heading capitalization style, list punctuation).
- Speculative performance concerns in shell scripts that have not been measured
  (e.g. "this `grep` could be replaced with a `sed`").
- Warnings about features described as future work or deferred to a later
  phase in spec documents.
- Severity emoji usage (`🔴`, `🟡`, `🟢`) in the existing `pr-review/`
  inline Claude prompt — that prompt is the live Claude-path prompt and
  intentionally uses that vocabulary; it will be retired in a later phase.
- Composite action input validation for optional inputs that have documented
  defaults — missing a guard on an optional input with a safe default is not a
  correctness issue.
