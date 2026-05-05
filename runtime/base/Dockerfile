# syntax=docker/dockerfile:1.7
# CI Claude Runtime — base image
# Spec: docs/superpowers/specs/2026-04-21-ci-claude-runtime-design.md §3.4 layer 1, §4.3 OCI labels, §7.3 image ENV

# Pinned by digest, not tag. Verified live 2026-05-01.
# v1: linux/amd64 only (GHA hosted runners are amd64). The --platform flag below
# is explicit so the build is unambiguous regardless of buildx default platform.
# Re-verify before bumping: docker manifest inspect --verbose node:20-slim
FROM --platform=linux/amd64 node:20-slim@sha256:3d0f05455dea2c82e2f76e7e2543964c30f6b7d673fc1a83286736d44fe4c41c

# Build args populated by docker/build-push-action. ALL are required so the
# image's OCI labels can stand alone as a reproducibility manifest (§4.3).
ARG PRIVATE_REF
ARG PRIVATE_SHA
ARG MARKETPLACE_SHA
ARG PUB_SHA
# CLI_VERSION pin (inquisitor pass 1 finding #5 mitigation). Default is the npm
# `stable` dist-tag value verified on 2026-05-01. The build workflow passes the
# value explicitly so it's also captured in the cache-key tuple and labels.
ARG CLI_VERSION=2.1.118

# §4.3 OCI labels — every image carries the pinned refs as labels so any built
# image is reproducible from its labels alone. Six labels total (R5):
LABEL org.opencontainers.image.source="https://github.com/glitchwerks/github-actions" \
      org.opencontainers.image.revision="${PUB_SHA}" \
      dev.glitchwerks.ci.private_ref="${PRIVATE_REF}" \
      dev.glitchwerks.ci.private_sha="${PRIVATE_SHA}" \
      dev.glitchwerks.ci.marketplace_sha="${MARKETPLACE_SHA}" \
      dev.glitchwerks.ci.cli_version="${CLI_VERSION}"

# Minimum runtime deps. Combine RUN steps to shrink layer count.
# `git` and `curl` are needed by the Claude Code CLI install path; `ca-certificates`
# for HTTPS; `jq` is required by smoke-test.sh's structured-output parser.
# `unzip` is required by `oven-sh/setup-bun@v1` (transitively used by
# `claude-code-action@v1`) to extract its tarball.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
      jq \
      unzip \
 && rm -rf /var/lib/apt/lists/*

# CVE-2022-24765 / safe.directory bake-in (#199, #197).
#
# `actions/checkout` writes the workspace as the host runner UID, but inside
# the container that owner does not match the running UID — git refuses to
# operate on the repo with `fatal: detected dubious ownership`. This trips
# `claude-code-action@v1`'s `git fetch` / `git hash-object` setup, blocking
# every workflow that touches the workspace via git.
#
# Use `--system` (writes /etc/gitconfig — read by every UID, no $HOME
# dependency) and `*` (any path — robust to nested git operations and to
# future workspace path changes). `--global` is insufficient because the
# bun-invoked TypeScript entrypoint of claude-code-action resolves $HOME
# differently than a typical shell step (PR #198 commit 7fd62e3 confirmed
# this empirically).
#
# Security note: `safe.directory '*'` disables the CVE-2022-24765 check
# globally inside the container. The CVE protected against an attacker
# planting a malicious `.git/config` in a directory the user cd's into.
# Inside an ephemeral GHA container with a workspace that we own, this
# threat does not apply. Spec §7.3 amendment captures the rationale.
RUN git config --system --add safe.directory '*'

# Install GitHub CLI (`gh`) from the official cli.github.com apt repo.
# Required by composite actions in this repo (pr-review, apply-fix, lint-failure,
# ci-failure, tag-claude) — they shell out to `gh` for PR diff fetching, status
# creation, comment posting, and dedup. claude-code-action@v1 also exposes gh
# subcommands to the AI via --allowedTools (Bash(gh pr diff:*), Bash(gh pr review:*),
# Bash(gh pr view:*)). See issue #194 for the full call-site map.
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
 && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends gh \
 && rm -rf /var/lib/apt/lists/*

# Install Claude Code CLI at the pinned version. The version flows from the
# manifest-table pin → CLI_VERSION ARG → this RUN → the cli_version OCI label.
# Reproducibility chain: a build with the same CLI_VERSION produces the same
# /usr/local/lib/node_modules/@anthropic-ai/claude-code tree (modulo npm's
# transient-dep pinning, which is captured by package-lock at npm registry side).
RUN npm install -g "@anthropic-ai/claude-code@${CLI_VERSION}"

# Layer order rationale (inquisitor pass 2 Charge 1 mitigation):
#   1. COPY shared/   — creates /opt/claude/.claude/ tree (root-owned by default)
#   2. chmod tree     — flatten dir/file modes to 0755/0644
#   3. useradd        — register passwd entry for UID 1001 with pw_dir=/opt/claude.
#                       /opt/claude EXISTS at this point (step 1 created it), so
#                       useradd has unambiguous semantics: create passwd entry
#                       only, do NOT auto-create the home dir or copy /etc/skel.
#   4. chown tree     — flip ownership of the now-existing tree to runner:runner.
#   5. symlink        — /root/.claude → /opt/claude/.claude (path-b satisfaction)
# Any future RUN inserted between (1) and (4) inherits root-ownership and breaks
# the perms-regression smoke check (R3) — that's the trip-wire.

# Materialized shared tree (built by extract-shared.sh) lands at /opt/claude/.claude/
# The build context's `shared/` directory is the OUT_DIR from the workflow's STAGE 2.
COPY --chmod=0755 shared/ /opt/claude/.claude/

# §6.2 STAGE 3 read-side note (applied here in base so overlays inherit):
# /opt/claude/.claude/ MUST be world-readable so a non-root consumer process can
# load agents, hooks, and CLAUDE.md. COPY --chmod=0755 sets directory mode;
# we still need to set file mode 0644.
RUN find /opt/claude/.claude -type f -exec chmod 0644 {} + \
 && find /opt/claude/.claude -type d -exec chmod 0755 {} +

# §13 Q1 mitigation (path c — passwd entry for UID 1001):
# `node:20-slim` does not have a passwd entry for UID 1001 by default. The
# entry is purely structural — code paths that call getpwuid(1001) get a
# valid struct passwd back with pw_dir=/opt/claude. The functional behavior
# is identical to path (a) because HOME=/opt/claude is set as ENV; we add
# the passwd entry so that any future code path resolving via passwd
# (rather than HOME env) does not silently fall back to a different root.
# `--no-create-home` is intentional: /opt/claude already exists from the COPY
# above; useradd should create the passwd entry only.
RUN useradd -u 1001 -d /opt/claude -s /bin/bash --no-create-home runner \
 && chown -R 1001:1001 /opt/claude

# §13 Q1 mitigation (path b — hard-coded /root/.claude): some Claude Code CLI
# versions resolve config from /root/.claude regardless of HOME. The symlink
# makes the same tree reachable from that path with no duplication.
RUN ln -s /opt/claude/.claude /root/.claude

# §7.3 image ENV — inherited by every overlay and every process the container runs.
# Consumer workflows must NOT override these; documented in §9.2.
ENV PATH_TO_CLAUDE_CODE_EXECUTABLE=/usr/local/bin/claude \
    HOME=/opt/claude

# §13 Q1 verification: Task 5 below proves all three CLI resolution paths
# (HOME env, /root/.claude, getpwuid(1001).pw_dir) reach the config tree.
# Each path is independently verified before the Dockerfile is committed.

# Default command is the claude binary. Smoke test overrides with `--print ...`.
ENTRYPOINT ["/usr/local/bin/claude"]
CMD ["--help"]
