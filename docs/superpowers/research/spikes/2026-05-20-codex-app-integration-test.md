---
title: Spike — Codex GitHub App Integration Test
date: 2026-05-20
issue: 275
epic: 273
status: in-progress (awaiting App install + observation)
---

# Codex GitHub App Integration Test

This PR is the test stimulus for issue #275: **does the OpenAI Codex GitHub App extend to org-owned repos under a ChatGPT subscription, or only to personal repos?**

## Why this matters

The current Codex-pivot spec (`docs/superpowers/specs/2026-05-20-codex-pivot.md`) assumes the entire PR-review surface must move to `openai/codex-action@v1.8` and be billed per-token against an OpenAI API key — because [prior research](../2026-05-20-codex-evaluation.md) (gap #2) could not verify whether the GitHub App's subscription coverage applies to org-owned repos.

If the App **does** cover `glitchwerks/*` repos under the existing subscription, then:

- The bespoke `pr-review/` composite action retires entirely (managed by OpenAI, no maintenance).
- The structured-output quality gate becomes the App's native review state (`CHANGES_REQUESTED` / `APPROVED`) instead of a custom JSON schema we have to author and parse.
- Estimated monthly cost drops from ~$232 (gpt-5.2-codex API) to **subscription-bundled** for the review surface — API spend would be limited to the four write-side workflows (`apply-fix`, `lint-failure`, `ci-failure`, `tag-respond`) that the App does not cover.

If the App **does not** extend to org-owned repos, the spec stays on its current path #1 (API-billed Action) without further modification.

## How to complete the spike (manual steps)

This is the part the router cannot automate — App installation requires browser-side OAuth consent.

The official integration is the **ChatGPT Codex Connector** GitHub App at [github.com/apps/chatgpt-codex-connector](https://github.com/apps/chatgpt-codex-connector) (the bare `github.com/apps/codex` URL is a different, unrelated private app). The supported install flow is via the OpenAI side, not by visiting the App page directly:

1. **Go to Codex** at [chatgpt.com/codex](https://chatgpt.com/codex) (logged in with the ChatGPT account that has the Plus/Pro subscription).
2. **Open Codex Settings** and locate the **GitHub** connector. Click **Connect**. You'll be redirected to GitHub's authorization page for the ChatGPT Codex Connector App.
3. **Authorize against the `glitchwerks` org** and choose the install scope:
   - Recommended for the spike: **only `glitchwerks/github-actions`**. Narrow blast radius.
   - Alternative: All repositories or any subset.
4. **Back in Codex Settings → Code review**, find the entry for `glitchwerks/github-actions` and toggle **Code review** on. Then either:
   - Toggle **Automatic reviews** so Codex reviews every new PR (preferred for the spike — it will pick up PR #276 automatically), or
   - Leave it off and post `@codex review` as a comment on PR #276 to trigger manually.
5. **Wait up to 30 minutes** for the first review to post. App-triggered reviews are not instantaneous; the cloud-side sandbox clones, indexes, and runs.
6. **Record observations in issue #275** using the checklist below.

> **Known footgun (community thread, March 2026):** some users hit "GitHub connector connected but unusable for private repos — OAuth token scope never applies." If the connector shows as connected in Codex Settings but the repo list is empty or stuck, the workaround per the [community thread](https://community.openai.com/t/github-connector-connected-but-unusable-for-private-repos-oauth-token-scope-never-applies/1365065) is to **revoke and re-authorize** from the GitHub side (Settings → Applications → ChatGPT Codex Connector → Revoke). `glitchwerks/github-actions` is public so this likely won't bite, but worth knowing.
>
> **EMU note:** for GitHub Enterprise Managed Users, an org owner must install the App for the org before users can connect repos. Doesn't apply to `glitchwerks` (personal org).

## Observation checklist

Fill these in on #275 once the App has (or hasn't) reviewed this PR:

- [ ] Did `@codex` (or whatever bot identity the App posts as) submit a review on this PR? Yes / No
- [ ] If yes, what GitHub login does it post as? (`@codex` / `@openai-codex[bot]` / other — verbatim)
- [ ] What is the review state? (`APPROVED` / `CHANGES_REQUESTED` / `COMMENTED`)
- [ ] Did the review reference any file **outside this PR's diff**? If yes, which? (This is the context-aware signal — diff-only reviews ≠ context-aware reviews.)
- [ ] Did GitHub or OpenAI surface any billing / rate-limit / "requires API access" notice on the App install, the PR, or the OpenAI dashboard?
- [ ] Did the existing Claude `pr-review` workflow also post a review? (Confirms side-by-side comparison data is available.)
- [ ] If both posted, copy a one-paragraph diff of style/depth between the two reviews into the issue.

## What "success" and "failure" look like

| Outcome | Interpretation | Action on the spec |
|---|---|---|
| `@codex` posts a context-aware review, no billing prompt | Subscription covers org repos. Big win. | Rewrite spec §5.1 to use App for pr-review; keep API path only for write-side workflows. |
| `@codex` posts but only references the diff (no outside-file context) | Works but context-aware claim is weaker than hoped. | Use App but plan a context-injection fallback; or stay on API path. |
| App installs but never posts on this PR within 24h | App may require explicit `@codex` mention, or coverage doesn't extend here. | Re-test with a comment trigger; if still nothing, treat as "API path required" and close. |
| Install or first review triggers a billing prompt / "subscribe to API" message | Subscription does not cover this surface. | Spec stays on current path #1. |

## Notes for the test PR itself

The diff this PR introduces is just this document — a research artifact, not production code. That keeps the test PR low-risk: no behavior changes, no workflow edits, easy to revert if anything unexpected happens.

The Codex App's review of this PR is the test signal. The content of this doc is the test stimulus — whatever Codex says about it (or doesn't say) is the data.
