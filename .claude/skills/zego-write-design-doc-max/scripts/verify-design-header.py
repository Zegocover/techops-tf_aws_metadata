#!/usr/bin/env python3
"""Deterministic check of the canonical six-line design-document header.

Replaces the old header-format check agent. Run by SKILL.md Stage 12 after the
design-writer returns, and again after any full-ladder revision.

Usage: verify-design-header.py <design-path> <ticket>

Exit 0 and print "OK" when the header is canonical.
Exit 1 and print one line per deviation (line number, observed, expected shape)
  so SKILL.md can fix the named lines deterministically with Edit and re-run.
Exit 2 on unreadable input / bad usage.

Line 2 is the load-bearing line: it must satisfy the consumer grep
`^JIRA: {TICKET}$` in .claude/skills/review/SKILL.md exactly. Lines 1 and 3-6
are non-empty-value prefix checks only (multi-word and URL values are valid).
"""

import re
import sys


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: verify-design-header.py <design-path> <ticket>")
        return 2
    path, ticket = sys.argv[1], sys.argv[2]
    try:
        with open(path, encoding="utf-8") as f:
            lines = f.read().splitlines()
    except OSError as exc:
        print(f"cannot read {path}: {exc}")
        return 2

    rules = [
        (r"^# Design: \S", "# Design: {feature_name}"),
        (rf"^JIRA: {re.escape(ticket)}$", f"JIRA: {ticket}"),
        (r"^Engineer: \S", "Engineer: {engineer}"),
        (r"^Requirements: \S", "Requirements: {requirements_source_path}"),
        (r"^Date: \S", "Date: {date}"),
        (r"^Branch: \S", "Branch: {branch}"),
    ]

    failures = []
    for i, (pattern, expected) in enumerate(rules):
        observed = lines[i] if i < len(lines) else "<missing>"
        if not re.search(pattern, observed):
            failures.append(
                f"line {i + 1}: got {observed!r}, expected shape {expected!r}"
            )

    if failures:
        print("\n".join(failures))
        return 1
    print("OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
