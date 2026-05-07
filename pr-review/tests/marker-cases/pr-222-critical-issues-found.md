**Claude finished @cbeaulieu-gt's task in 2m 16s** —— [View job](https://github.com/glitchwerks/github-actions/actions/runs/25465608989)

---
### PR Review Complete

I've reviewed PR #222 which refreshes the consumer-facing README for Phase 5+ container-pinned workflows. The PR successfully addresses most of the stated objectives, but I found **two critical inconsistencies** in the quick-start examples that need fixing before merge.

---

### What's Working Well ✅

**Accurate updates (6/8 changes):**

1. **Intro refresh** (line 3) — capability list is comprehensive and accurate
2. **Authentication clarification** (line 5) — clearly explains the two-tier auth model (OAuth token + App credentials)
3. **Actions table** (line 14) — `apply-fix` row added
4. **Permissions Reference** (lines 22, 28-32) — excellent addition of "Container pull permission" blockquote, all rows correctly show `packages: read`, includes #192 citation
5. **CI Failure quick-start** (lines 310-322) — `claude-ci-failure.yml@v2` + `packages: read` ✅
6. **Lint Fix quick-start** (lines 359-383) — `claude-lint-failure.yml@v2` + `packages: read` ✅
7. **Apply Fix manual trigger** (line 430) — `claude-apply-fix.yml` ✅
8. **GHCR section** (lines 229-259) — well-structured, explains both Internal visibility and per-repo grant patterns, clear explanation of why `packages: read` is mandatory

The new GHCR section is particularly well-written. The distinction between "necessary condition" (visibility setting) and "also necessary" (`packages: read` permission) is clear and will prevent the #192 trap.

---

### Critical Issues Found 🚨

The permissions table (lines 28-29) correctly lists `packages: read` for **all** container-pinned workflows, but two quick-start examples are missing it:

#### 1. PR Review quick-start (lines 52-54)

**Current:**
```yaml
permissions:
  contents: read
  pull-requests: write
```

**Should be (per permissions table line 28):**
```yaml
permissions:
  contents: read
  pull-requests: write
  packages: read
```

#### 2. Tag Claude quick-start (lines 85-88)

**Current:**
```yaml
permissions:
  contents: write
  issues: write
  pull-requests: write
```

**Should be (per permissions table line 29):**
```yaml
permissions:
  contents: write
  issues: write
  pull-requests: write
  packages: read
```

**Impact:** Consumers who copy-paste these examples will hit the `manifest unknown` error described in #192 and the new GHCR section. Since these are the **first two quick-start examples** most consumers encounter, this undermines the entire PR's goal of preventing the #192 trap.

**Why this matters:** The PR correctly updates the CI Failure, Lint Fix, and Apply Fix examples (changes #5, #6, #7), but misses the two most commonly used workflows. This creates an inconsistency where the permissions table says one thing but the examples show another.

---

### Recommendations

1. **Before merge:** Add `packages: read` to:
   - PR Review example at line 54 (after `pull-requests: write`)
   - Tag Claude example at line 88 (after `pull-requests: write`)

2. **Optional improvement:** Consider adding a brief inline comment in the quick-start examples explaining why `packages: read` is required, e.g.:
   ```yaml
   permissions:
     contents: read
     pull-requests: write
     packages: read  # Required for GHCR overlay image pull (see "GHCR package access" section)
   ```
   This would make the examples more self-documenting, but the current permissions table blockquote (line 22) already explains it well.

3. **Validation:** After fixing, verify all 5 quick-start examples match their corresponding permissions table rows.

---

### Test Plan Status

From the PR body test plan:
- ✅ All 4 quick-start YAML examples reference Phase 5 workflow names (verified)
- ✅ Permissions table lists `packages: read` for every container-pinned row (verified)
- ✅ New GHCR-access section present (verified — lines 229-259)
- ✅ Commit on correct branch (verified — `issue-219-readme-onboarding`)
- ⏸️ CI lint workflow — cannot verify without pushing
- ⏸️ Reviewer eyes on GHCR section — **this review confirms the click-paths and technical accuracy are correct**

---

### Summary

Strong PR that addresses the Phase 5 documentation gap and the #192 trap. The permissions table, GHCR section, and 3/5 quick-start examples are excellent. The two missing `packages: read` entries in PR Review and Tag Claude examples need fixing before merge to ensure consistency and prevent the exact error this PR aims to prevent.

**Recommended action:** Add `packages: read` to lines 54 and 88, then merge.

---

### Tasks
- [x] Retrieve PR diff
- [x] Read README.md to understand full context
- [x] Review workflow name updates
- [x] Verify `packages: read` additions
- [x] Check GHCR access documentation
- [x] Evaluate quick-start examples
- [x] Post comprehensive review
