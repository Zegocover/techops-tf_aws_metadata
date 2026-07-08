#!/usr/bin/env python3
"""Step 6b: deterministically reconcile a task spec's two contract fields.

Verifies (and corrects in place) the `branch:` frontmatter field and the
`Depends on:` body-header field against the canonical values SKILL.md
dispatched to the task-writer. Replaces the old inline Read/Edit/re-Read
procedure; same semantics: region-scoped location and uniqueness, trimmed
comparison, single-line correction, post-condition assertion.

Usage: verify-task-contract.py <spec-path> <branch> <depends-on>

Prints "OK" (no drift), or one correction note per corrected field
("{spec filename}: {field} corrected from '<got>' to '<expected>'"), or a
"HALT: ..." line for the structural failures the old step 6b enumerated.

Exit 0 on OK / corrections applied; exit 2 on HALT.
"""

import re
import sys
from typing import NoReturn


def halt(msg: str) -> NoReturn:
    print(f"HALT: {msg}")
    sys.exit(2)


def read_lines(path: str) -> list[str]:
    try:
        with open(path, encoding="utf-8") as f:
            return f.read().splitlines(keepends=True)
    except OSError:
        halt(f"task spec not found at {path}")


def frontmatter_region(lines: list[str], path: str) -> range:
    """Lines between the first and second `---` delimiters."""
    delims = [i for i, line in enumerate(lines) if line.rstrip("\n") == "---"]
    if len(delims) < 2:
        halt(f"task spec frontmatter block malformed at {path}")
    return range(delims[0] + 1, delims[1])


def body_header_region(lines: list[str], path: str) -> range:
    """Lines between the H1 title and the first `##` heading that follows it.

    HTML comment lines do not begin with the field token, so the startswith
    anchor cannot match them.
    """
    h1 = next((i for i, line in enumerate(lines) if line.startswith("# ")), None)
    if h1 is None:
        halt(f"task spec body-header region malformed at {path}")
    h2 = next(
        (i for i in range(h1 + 1, len(lines)) if lines[i].startswith("## ")), None
    )
    if h2 is None:
        halt(f"task spec body-header region malformed at {path}")
    return range(h1 + 1, h2)


def reconcile(
    lines: list[str], region: range, token: str, canonical: str, path: str
) -> str | None:
    """Correct the single `token` line within `region` in place.

    Returns a correction note when a correction was applied, else None. Trimmed
    comparison: a whitespace-only difference is not drift and is left untouched.
    """
    matches = [i for i in region if lines[i].startswith(token)]
    if not matches:
        halt(f"task spec {token} line absent at {path}")
    if len(matches) > 1:
        halt(f"task spec {token} line not unique at {path}")
    i = matches[0]
    current = lines[i][len(token) :].strip()
    if not current:
        halt(f"task spec {token} line empty at {path}")
    if current == canonical:
        return None
    lines[i] = f"{token} {canonical}\n"
    filename = path.rsplit("/", 1)[-1]
    return f"{filename}: {token} corrected from '{current}' to '{canonical}'"


def write_and_verify(path: str, lines: list[str], branch: str, depends: str) -> None:
    """Write the reconciled lines and assert the re-read post-condition."""
    try:
        with open(path, "w", encoding="utf-8") as f:
            f.write("".join(lines))
    except OSError:
        halt(f"step 6b write failed at {path}")
    # Post-condition: re-read and assert both fields now hold the canonical
    # values. Normalise post-token whitespace first so the substring assertion
    # matches reconcile()'s trimmed tolerance — a cosmetically-spaced sibling
    # field (e.g. `Depends on:  none`) that was correctly left uncorrected must
    # not false-HALT alongside a corrected field.
    try:
        with open(path, encoding="utf-8") as f:
            reread = f.read()
    except OSError:
        halt(f"step 6b re-read failed at {path}")
    norm = re.sub(r"(?m)^(branch:|Depends on:)\s*", r"\1 ", reread)
    if f"branch: {branch}" not in norm or f"Depends on: {depends}" not in norm:
        halt(f"step 6b post-condition failed at {path}")


def main() -> int:
    if len(sys.argv) != 4:
        halt("usage: verify-task-contract.py <spec-path> <branch> <depends-on>")
    path, branch, depends = sys.argv[1], sys.argv[2], sys.argv[3]
    lines = read_lines(path)

    # Locate both regions on the unmutated lines, then reconcile each field.
    fm_region = frontmatter_region(lines, path)
    body_region = body_header_region(lines, path)
    notes = [
        note
        for note in (
            reconcile(lines, fm_region, "branch:", branch, path),
            reconcile(lines, body_region, "Depends on:", depends, path),
        )
        if note is not None
    ]

    if notes:
        write_and_verify(path, lines, branch, depends)
        print("\n".join(notes))
    else:
        print("OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
