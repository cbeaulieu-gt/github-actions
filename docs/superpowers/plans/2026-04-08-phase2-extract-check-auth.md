# Phase 2: Extract check-auth to TypeScript — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract the 37-line inline bash authorization logic from `check-auth/action.yml` into tested TypeScript, producing the first ncc-bundled `dist/` output in the repo.

**Architecture:** Pure logic in `src/lib/auth.ts` (two functions, no side effects). Entry point in `src/check-auth/index.ts` reads env vars, calls lib, writes `authorized` output via `@actions/core`. Bundle via `@vercel/ncc` to `check-auth/dist/check-auth.js`. Action YAML becomes a thin wrapper that sets env vars and runs the node script.

**Tech Stack:** TypeScript, @actions/core, @vercel/ncc, Jest + ts-jest

**Tracks:** Issue #99

---

## File Map

| File | Purpose |
|---|---|
| `src/lib/auth.ts` | `checkAllowlist()` and `checkAssociation()` — pure logic, no deps |
| `src/check-auth/index.ts` | Entry point — reads env, calls lib, writes GITHUB_OUTPUT |
| `tests/lib/auth.test.ts` | Unit tests for auth lib functions |
| `tests/check-auth.test.ts` | Integration tests for entry point (mocked @actions/core) |
| `check-auth/dist/check-auth.js` | ncc bundle (committed to repo) |
| `check-auth/action.yml` | Replace bash with `node` invocation |
| `package.json` | Add ncc build command to `build` script |

---

### Task 1: TDD Auth Library Functions

**Files:**
- Create: `src/lib/auth.ts`
- Create: `tests/lib/auth.test.ts`

- [ ] **Step 1: Write failing tests for `checkAllowlist`**

```typescript
// tests/lib/auth.test.ts
import { checkAllowlist, checkAssociation } from '../../src/lib/auth';

describe('checkAllowlist', () => {
  it('returns true when actor is in the list (exact match)', () => {
    expect(checkAllowlist('alice', 'alice,bob')).toBe(true);
  });

  it('returns true when actor matches case-insensitively', () => {
    expect(checkAllowlist('Alice', 'alice,bob')).toBe(true);
  });

  it('returns true when list has spaces around commas', () => {
    expect(checkAllowlist('bob', 'alice, bob, charlie')).toBe(true);
  });

  it('returns false when actor is not in the list', () => {
    expect(checkAllowlist('eve', 'alice,bob')).toBe(false);
  });

  it('does not partial-match substrings', () => {
    expect(checkAllowlist('ali', 'alice,bob')).toBe(false);
  });

  it('returns false when list is empty string', () => {
    expect(checkAllowlist('alice', '')).toBe(false);
  });
});

describe('checkAssociation', () => {
  it('returns true for OWNER', () => {
    expect(checkAssociation('OWNER')).toBe(true);
  });

  it('returns true for MEMBER', () => {
    expect(checkAssociation('MEMBER')).toBe(true);
  });

  it('returns true for COLLABORATOR', () => {
    expect(checkAssociation('COLLABORATOR')).toBe(true);
  });

  it('returns false for CONTRIBUTOR', () => {
    expect(checkAssociation('CONTRIBUTOR')).toBe(false);
  });

  it('returns false for FIRST_TIME_CONTRIBUTOR', () => {
    expect(checkAssociation('FIRST_TIME_CONTRIBUTOR')).toBe(false);
  });

  it('returns false for NONE', () => {
    expect(checkAssociation('NONE')).toBe(false);
  });

  it('returns false for empty string', () => {
    expect(checkAssociation('')).toBe(false);
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `npx jest tests/lib/auth.test.ts --verbose`

Expected: FAIL — `Cannot find module '../../src/lib/auth'`

- [ ] **Step 3: Implement auth library**

```typescript
// src/lib/auth.ts

/**
 * Checks whether an actor is in a comma-separated allowlist (case-insensitive).
 *
 * The allowlist takes full precedence over association checks when non-empty.
 * Matches are exact per-entry — no substring matching.
 *
 * @param actor - The GitHub username to check
 * @param authorizedUsers - Comma-separated list of authorized usernames
 * @returns true if actor is in the list
 */
export function checkAllowlist(actor: string, authorizedUsers: string): boolean {
  if (!authorizedUsers) {
    return false;
  }

  const actorLower = actor.toLowerCase();
  const users = authorizedUsers.split(',').map((u) => u.trim().toLowerCase());
  return users.includes(actorLower);
}

/**
 * Checks whether a GitHub author_association grants authorization.
 *
 * Only OWNER, MEMBER, and COLLABORATOR are considered authorized.
 * All other associations (CONTRIBUTOR, FIRST_TIME_CONTRIBUTOR, NONE, etc.) are rejected.
 *
 * @param association - The author_association value from the GitHub event
 * @returns true if the association grants access
 */
export function checkAssociation(association: string): boolean {
  const allowed = ['OWNER', 'MEMBER', 'COLLABORATOR'];
  return allowed.includes(association);
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `npx jest tests/lib/auth.test.ts --verbose`

Expected: All 13 tests pass

- [ ] **Step 5: Run type-check**

Run: `npm run build`

Expected: Exit 0

- [ ] **Step 6: Commit**

```
git add src/lib/auth.ts tests/lib/auth.test.ts
git commit -m "feat: add checkAllowlist and checkAssociation auth library

Pure functions extracted from check-auth inline bash. Case-insensitive
allowlist matching, association check for OWNER/MEMBER/COLLABORATOR.

Part of #99"
```

---

### Task 2: TDD Entry Point

**Files:**
- Create: `src/check-auth/index.ts`
- Create: `tests/check-auth.test.ts`

The entry point reads inputs from environment variables (set by the action YAML `env:` block), calls the lib functions, and writes `authorized=true/false` to `$GITHUB_OUTPUT` via `@actions/core`.

The logic mirrors the existing bash exactly:
1. If `AUTHORIZED_USERS` is non-empty → check allowlist only (association is ignored)
2. Else if `REQUIRE_ASSOCIATION` is `'true'` → check association
3. Else → authorized (association check disabled)

- [ ] **Step 1: Write failing integration tests**

```typescript
// tests/check-auth.test.ts
import * as core from '@actions/core';

// Mock @actions/core before importing the entry point
jest.mock('@actions/core');

const mockedCore = jest.mocked(core);

// Helper to run the entry point with specific env vars
async function runCheckAuth(env: Record<string, string>): Promise<void> {
  // Set env vars
  const originalEnv = { ...process.env };
  Object.assign(process.env, env);

  // Clear module cache so the entry point re-reads env on each run
  jest.resetModules();
  jest.mock('@actions/core');

  try {
    await import('../src/check-auth/index');
  } finally {
    // Restore env
    process.env = originalEnv;
  }
}

beforeEach(() => {
  jest.clearAllMocks();
});

describe('check-auth entry point', () => {
  describe('allowlist mode', () => {
    it('authorizes when actor is in allowlist (case-insensitive)', async () => {
      await runCheckAuth({
        ACTOR: 'Alice',
        ASSOCIATION: 'NONE',
        AUTHORIZED_USERS: 'alice,bob',
        REQUIRE_ASSOCIATION: 'true',
      });

      const setOutput = jest.mocked(core).setOutput;
      expect(setOutput).toHaveBeenCalledWith('authorized', 'true');
    });

    it('rejects when actor is not in allowlist (ignores OWNER association)', async () => {
      await runCheckAuth({
        ACTOR: 'eve',
        ASSOCIATION: 'OWNER',
        AUTHORIZED_USERS: 'alice,bob',
        REQUIRE_ASSOCIATION: 'true',
      });

      const setOutput = jest.mocked(core).setOutput;
      expect(setOutput).toHaveBeenCalledWith('authorized', 'false');
    });
  });

  describe('association mode (no allowlist)', () => {
    it('authorizes OWNER', async () => {
      await runCheckAuth({
        ACTOR: 'someone',
        ASSOCIATION: 'OWNER',
        AUTHORIZED_USERS: '',
        REQUIRE_ASSOCIATION: 'true',
      });

      const setOutput = jest.mocked(core).setOutput;
      expect(setOutput).toHaveBeenCalledWith('authorized', 'true');
    });

    it('authorizes MEMBER', async () => {
      await runCheckAuth({
        ACTOR: 'someone',
        ASSOCIATION: 'MEMBER',
        AUTHORIZED_USERS: '',
        REQUIRE_ASSOCIATION: 'true',
      });

      const setOutput = jest.mocked(core).setOutput;
      expect(setOutput).toHaveBeenCalledWith('authorized', 'true');
    });

    it('authorizes COLLABORATOR', async () => {
      await runCheckAuth({
        ACTOR: 'someone',
        ASSOCIATION: 'COLLABORATOR',
        AUTHORIZED_USERS: '',
        REQUIRE_ASSOCIATION: 'true',
      });

      const setOutput = jest.mocked(core).setOutput;
      expect(setOutput).toHaveBeenCalledWith('authorized', 'true');
    });

    it('rejects FIRST_TIME_CONTRIBUTOR', async () => {
      await runCheckAuth({
        ACTOR: 'newbie',
        ASSOCIATION: 'FIRST_TIME_CONTRIBUTOR',
        AUTHORIZED_USERS: '',
        REQUIRE_ASSOCIATION: 'true',
      });

      const setOutput = jest.mocked(core).setOutput;
      expect(setOutput).toHaveBeenCalledWith('authorized', 'false');
    });

    it('rejects NONE', async () => {
      await runCheckAuth({
        ACTOR: 'stranger',
        ASSOCIATION: 'NONE',
        AUTHORIZED_USERS: '',
        REQUIRE_ASSOCIATION: 'true',
      });

      const setOutput = jest.mocked(core).setOutput;
      expect(setOutput).toHaveBeenCalledWith('authorized', 'false');
    });
  });

  describe('association disabled', () => {
    it('authorizes everyone when require_association is false and no allowlist', async () => {
      await runCheckAuth({
        ACTOR: 'anyone',
        ASSOCIATION: 'NONE',
        AUTHORIZED_USERS: '',
        REQUIRE_ASSOCIATION: 'false',
      });

      const setOutput = jest.mocked(core).setOutput;
      expect(setOutput).toHaveBeenCalledWith('authorized', 'true');
    });
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `npx jest tests/check-auth.test.ts --verbose`

Expected: FAIL — `Cannot find module '../src/check-auth/index'`

- [ ] **Step 3: Implement entry point**

```typescript
// src/check-auth/index.ts
import * as core from '@actions/core';
import { checkAllowlist, checkAssociation } from '../lib/auth';

const actor = process.env.ACTOR ?? '';
const association = process.env.ASSOCIATION ?? '';
const authorizedUsers = process.env.AUTHORIZED_USERS ?? '';
const requireAssociation = process.env.REQUIRE_ASSOCIATION ?? 'true';

let authorized = false;

if (authorizedUsers) {
  // Allowlist takes full precedence — association is ignored
  authorized = checkAllowlist(actor, authorizedUsers);
  if (authorized) {
    core.info(`Authorized via allowlist: ${actor}`);
  } else {
    core.info(`Not authorized: ${actor} is not in the authorized_users list. Skipping.`);
  }
} else if (requireAssociation === 'true') {
  // No allowlist — fall back to association check
  authorized = checkAssociation(association);
  if (authorized) {
    core.info(`Authorized via association: ${actor} (${association})`);
  } else {
    core.info(`Not authorized: ${actor} has association '${association}'. Skipping.`);
  }
} else {
  // Association check disabled — all commenters authorized
  authorized = true;
  core.info('Association check disabled — all commenters authorized.');
}

core.setOutput('authorized', authorized ? 'true' : 'false');
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `npx jest tests/check-auth.test.ts --verbose`

Expected: All 8 tests pass

- [ ] **Step 5: Run full test suite**

Run: `npm test`

Expected: All tests pass (auth lib + entry point + tokens)

- [ ] **Step 6: Commit**

```
git add src/check-auth/index.ts tests/check-auth.test.ts
git commit -m "feat: add check-auth entry point

Reads ACTOR, ASSOCIATION, AUTHORIZED_USERS, REQUIRE_ASSOCIATION from
env vars. Delegates to lib/auth functions. Writes authorized output
via @actions/core.

Part of #99"
```

---

### Task 3: Build Pipeline + ncc Bundle

**Files:**
- Modify: `package.json` (build script)
- Create: `check-auth/dist/check-auth.js` (ncc output)

This is the first ncc bundle in the repo. The `build` script needs to type-check AND bundle.

- [ ] **Step 1: Update `package.json` build script**

Change the `"build"` script from:
```json
"build": "tsc --noEmit",
```
to:
```json
"build": "tsc --noEmit && ncc build src/check-auth/index.ts -o check-auth/dist --source-map --license licenses.txt",
```

The `--source-map` flag adds a source map for debugging. The `--license` flag extracts third-party licenses into a separate file.

- [ ] **Step 2: Run the build**

Run: `npm run build`

Expected: Exit 0. Creates `check-auth/dist/check-auth.js` (and `check-auth.js.map`, `licenses.txt`).

- [ ] **Step 3: Verify the bundle runs**

Run: `node check-auth/dist/check-auth.js`

Expected: Runs and exits (may log "Association check disabled" since env vars are unset — that's fine, it proves the bundle loads and executes).

- [ ] **Step 4: Run build:check to verify dist/ is committed correctly**

Run: `npm run build:check`

Expected: Fails with "dist/ is stale" because the bundle isn't committed yet. This is expected — confirms the check works.

- [ ] **Step 5: Commit the bundle and build script update**

```
git add package.json check-auth/dist/
git commit -m "build: add ncc bundle for check-auth

First action bundle in the repo. Updates build script to type-check
then bundle via ncc. dist/ is committed and checked for staleness in CI.

Part of #99"
```

- [ ] **Step 6: Verify build:check now passes**

Run: `npm run build:check`

Expected: Exit 0 — dist/ matches the build output.

---

### Task 4: Wire action.yml

**Files:**
- Modify: `check-auth/action.yml`

Replace the 37-line inline bash block with a single node invocation. The env vars bridge the GitHub context expressions into the node script's `process.env`.

- [ ] **Step 1: Replace the bash step in `check-auth/action.yml`**

The current file content is:
```yaml
name: 'Check Authorization'
description: 'Checks whether the comment author is authorized to trigger Claude based on allowlist or author_association'

inputs:
  require_association:
    description: 'Only allow OWNER, MEMBER, and COLLABORATOR when no allowlist is set'
    required: false
    default: 'true'
  authorized_users:
    description: 'Comma-separated list of GitHub usernames authorized to trigger Claude. When set, overrides require_association.'
    required: false
    default: ''

outputs:
  authorized:
    description: "'true' if the comment author is authorized, 'false' otherwise"
    value: ${{ steps.check.outputs.authorized }}

runs:
  using: composite
  steps:
    - name: Evaluate authorization
      id: check
      shell: bash
      run: |
        ACTOR="${{ github.event.comment.user.login }}"
        ...37 lines of bash...
```

Replace the entire step with:
```yaml
    - name: Evaluate authorization
      id: check
      shell: bash
      env:
        ACTOR: ${{ github.event.comment.user.login }}
        ASSOCIATION: ${{ github.event.comment.author_association }}
        AUTHORIZED_USERS: ${{ inputs.authorized_users }}
        REQUIRE_ASSOCIATION: ${{ inputs.require_association }}
      run: node "${{ github.action_path }}/dist/check-auth.js"
```

Keep the `name`, `description`, `inputs`, `outputs` sections unchanged.

- [ ] **Step 2: Verify actionlint passes**

Run: `actionlint check-auth/action.yml` (if installed locally, otherwise skip — CI will catch it)

- [ ] **Step 3: Commit**

```
git add check-auth/action.yml
git commit -m "refactor: replace check-auth inline bash with node invocation

Replaces 37 lines of inline bash with a single node command.
Env vars bridge GitHub context expressions into the TypeScript entry point.

closes #99"
```

---

### Task 5: Final Smoke Test

- [ ] **Step 1: Run full test suite**

Run: `npm test`

Expected: All tests pass (auth lib + check-auth entry point + tokens)

- [ ] **Step 2: Run type-check + build**

Run: `npm run build`

Expected: Exit 0, bundle regenerated

- [ ] **Step 3: Run build:check**

Run: `npm run build:check`

Expected: Exit 0 — dist/ is up to date

- [ ] **Step 4: Verify git status is clean**

Run: `git status`

Expected: Nothing to commit, working tree clean

- [ ] **Step 5: Review commit log**

Run: `git log --oneline -5`

Expected: 4 commits on this branch:
1. refactor: replace check-auth inline bash with node invocation
2. build: add ncc bundle for check-auth
3. feat: add check-auth entry point
4. feat: add checkAllowlist and checkAssociation auth library

---

## Post-Completion

After all tasks pass locally:

1. Push the branch and open a PR against `main`
2. Verify `test.yml`, `build-check.yml`, and `lint.yml` (actionlint) pass in CI
3. After merge: trigger a `@claude` comment on a test PR to verify tag-claude still invokes check-auth correctly (dogfood verification per spec)
