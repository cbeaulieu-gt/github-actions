# severity-regex.sh — source this file; do not execute directly.
# Provides SEVERITY_BLOCKER_RE (combined) and per-bucket patterns.
SEVERITY_BLOCKER_RE='🔴 Critical|Critical \(BLOCKING\)|🟡 High-Priority|\*\*MAJOR\*\*|\*\*BLOCKING\*\*'
SEVERITY_CRITICAL_RE='🔴 Critical|Critical \(BLOCKING\)|\*\*BLOCKING\*\*'
SEVERITY_HIGH_RE='🟡 High-Priority|\*\*MAJOR\*\*'
SEVERITY_MEDIUM_RE='🟢 Medium'
SEVERITY_LOW_RE='\bNit\b'
