# MCP allowlist security checklist

This document defines the minimum review gate for adding MCP servers to the
Claude-powered reusable actions.

It supports the design in
[`#53`](https://github.com/glitchwerks/github-actions/issues/53). It does not
enable MCP servers by itself.

## Scope

The checklist applies before adding any MCP server to `pr-review` or
`tag-claude`.

Consumers must select servers by allowlisted name only. Consumers must not
provide package sources, command arguments, registry URLs, or token wiring.

## Required review record

Every allowlist entry should document:

- Consumer-facing server name.
- Official MCP Registry name, when available.
- Publisher prefix and why it is trusted enough for this action.
- Exact package name and pinned version.
- Package integrity hash or equivalent lockfile proof.
- Install command and proof that install scripts are disabled.
- Token source and minimum required permissions.
- Whether the server expands the current `allowedTools` blast radius.
- Failure behavior when install, startup, or server execution fails.
- Reviewer who approved the entry.

## Blocking checklist

Before merge, every new allowlist entry must satisfy:

- [ ] Registry entry checked against the approved publisher-prefix list.
- [ ] Exact version is pinned.
- [ ] Integrity hash or lockfile entry is recorded.
- [ ] Install path disables package lifecycle scripts.
- [ ] Token permissions are documented and minimized.
- [ ] `allowedTools` impact is documented for `pr-review`.
- [ ] Unknown requested server names fail loudly.
- [ ] MCP configuration is built with structured JSON, not shell string
      interpolation.
- [ ] The allowlist lookup is exact-match only.
- [ ] Crash/install failure behavior is specified.

## Structured JSON rule

Build `mcp_config` with `jq` or another structured JSON builder. Do not build
JSON by concatenating shell strings.

The `mcps` input should be parsed into exact names, trimmed, de-duplicated, and
looked up in a fixed allowlist. Pattern matching is not sufficient for this
boundary.

## Token-scope rule

An MCP server must not receive the full caller-granted token by default.

If the server cannot operate with a narrower token, the action should document
that limitation and print a warning before enabling the server. The warning
should state that enabling the server expands the action's blast radius beyond
the current shell command allowlist.

## Failure behavior

Choose and document one behavior for each allowlisted server:

- **Fail closed:** stop the action when the server cannot be installed or
  started.
- **Warn and continue without MCP:** continue current behavior without the
  server.

Silent degradation is not allowed.

## CODEOWNERS expectation

Allowlist files and this checklist are security-sensitive. They should be owned
by the same reviewers who approve token, package-source, and `allowedTools`
changes.
