**Claude finished @cbeaulieu-gt's task in 1m 30s** —— [View job](https://github.com/glitchwerks/github-actions/actions/runs/99999000002)

---
### PR Review Complete

I've reviewed this pull request and found findings at multiple severity levels.

### Findings

#### 🔴 Critical (BLOCKING)

**Unvalidated input passed directly to shell command**

The `run_command` function at line 42 constructs a shell command by concatenating
user-supplied input without sanitisation. An attacker who controls the input can
inject arbitrary shell commands.

```python
# current — dangerous
subprocess.run(f"git checkout {branch_name}", shell=True)
```

Fix: use the list form and disable `shell=True`:

```python
subprocess.run(["git", "checkout", branch_name], check=True)
```

#### 🟡 High-Priority (MAJOR)

**Missing error handling on network call**

`fetch_data()` at line 87 makes an HTTP request with no timeout and no exception
handling. A hung upstream service will block the workflow indefinitely.

Add a timeout and wrap in a try/except:

```python
response = requests.get(url, timeout=10)
response.raise_for_status()
```

#### 🟢 Medium

**Magic number should be a named constant**

Line 114 uses the literal `3600` for a cache TTL. Define a module-level constant
`CACHE_TTL_SECONDS = 3600` to make the intent clear and the value easy to change.

#### Nit

**Redundant `else` after `return`**

Line 201 has `else:` after a `return` in the preceding `if` block. The `else`
is unnecessary and can be removed to reduce nesting.

---

Verdict: BLOCK

<!-- claude-pr-review-summary-v1
{
  "schemaVersion": 1,
  "findings": {
    "critical": 1,
    "high": 1,
    "medium": 1,
    "low": 1
  }
}
-->
