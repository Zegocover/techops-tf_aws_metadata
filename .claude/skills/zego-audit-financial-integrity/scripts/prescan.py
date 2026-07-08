#!/usr/bin/env python3
"""
prescan.py - deterministic pre-scan for the audit-financial-integrity skill.

Parses a unified diff (from `git diff` or `gh pr diff --patch`) and flags
high-signal, regex-able indicators of financially-nefarious or malicious code,
with file:line locations and whether the line was ADDED or REMOVED. Output is a
list of *leads* (starting points), NOT verdicts: the reviewing model confirms or
dismisses each with reasoning, using the reference catalogues.

Design notes:
- Standard library only. No network required.
- Removed lines are scanned too (deleting a security control is a finding).
- If gitleaks or osv-scanner are on PATH, their output is folded in
  opportunistically (gitleaks scans the diff via stdin, osv-scanner scans changed
  manifests); absence is fine.

Usage:
    python3 prescan.py --diff /tmp/pr.diff [--repo .] [--out /tmp/leads.json]
    git diff --merge-base origin/main...HEAD | python3 prescan.py --diff - --out /tmp/leads.json
"""

from __future__ import annotations

import argparse
import json
import math
import re
import shutil
import subprocess
import sys
from collections.abc import Iterator
from dataclasses import asdict, dataclass
from typing import Any

# One parsed diff line: (filepath, lineno, change, raw_line).
DiffLine = tuple[str, int, str, str]


# --------------------------------------------------------------------------- #
# Detectors. Each: (category, severity_hint, regex, scope) where scope is
# "added" | "removed" | "both". These are DETECTION patterns (strings to look
# for), not executable payloads.
# --------------------------------------------------------------------------- #
def rx(p: str) -> re.Pattern[str]:
    return re.compile(p, re.IGNORECASE)


DETECTORS = [
    # --- Cryptocurrency wallet addresses (financial diversion / ransomware) ---
    (
        "crypto-wallet",
        "critical",
        re.compile(r"\b(bc1|tb1)[0-9ac-hj-np-z]{11,71}\b"),
        "added",
    ),  # bech32 BTC
    (
        "crypto-wallet",
        "critical",
        re.compile(r"\b[13][1-9A-HJ-NP-Za-km-z]{25,34}\b"),
        "added",
    ),  # legacy/P2SH BTC
    (
        "crypto-wallet",
        "critical",
        re.compile(r"\b0x[a-fA-F0-9]{40}\b"),
        "added",
    ),  # ETH/EVM (also hashes - triage)
    (
        "crypto-wallet",
        "critical",
        re.compile(r"\b[48][0-9A-Za-z]{94,105}\b"),
        "added",
    ),  # Monero
    (
        "crypto-wallet",
        "high",
        rx(r"\b(ltc1|bitcoincash:|cosmos1|terra1)[0-9A-Za-z]{20,}\b"),
        "added",
    ),
    ("crypto-wallet", "high", rx(r"stratum\+tcp://"), "added"),  # mining pool
    (
        "crypto-miner",
        "high",
        rx(r"\b(xmrig|cpuminer|minerd|ethminer|nbminer|coinhive)\b"),
        "added",
    ),
    # --- Secrets / keys / tokens ---
    ("secret", "critical", rx(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"), "added"),
    (
        "secret",
        "critical",
        re.compile(r"\bAKIA[0-9A-Z]{16}\b"),
        "added",
    ),  # AWS access key id
    (
        "secret",
        "critical",
        rx(r"\b(sk|rk)_live_[0-9a-zA-Z]{10,}\b"),
        "added",
    ),  # Stripe live
    (
        "secret",
        "high",
        re.compile(r"\bgh[pousr]_[0-9A-Za-z]{20,}\b"),
        "added",
    ),  # GitHub tokens
    ("secret", "high", rx(r"\bxox[baprs]-[0-9A-Za-z-]{10,}\b"), "added"),  # Slack
    ("secret", "high", rx(r"\bAIza[0-9A-Za-z_\-]{35}\b"), "added"),  # Google API key
    (
        "secret",
        "high",
        re.compile(
            r"\beyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{6,}\b",
        ),
        "added",
    ),  # JWT
    (
        "secret",
        "high",
        rx(
            r"(password|passwd|pwd|secret|api[_-]?key|access[_-]?key|client[_-]?secret|token)\s*[:=]\s*['\"][^'\"]{8,}['\"]"
        ),
        "added",
    ),
    # --- Hardcoded financial identifiers ---
    (
        "financial-identifier",
        "high",
        re.compile(r"\b[A-Z]{2}\d{2}[A-Z0-9]{11,30}\b"),
        "added",
    ),  # IBAN
    (
        "financial-identifier",
        "medium",
        re.compile(r"\b\d{2}-\d{2}-\d{2}\b"),
        "added",
    ),  # UK sort code (triage)
    (
        "financial-identifier",
        "high",
        rx(
            r"\b(iban|sort[_ ]?code|account[_ ]?number|beneficiary|payee)\b\s*[:=]\s*['\"]",
        ),
        "added",
    ),
    # --- Dynamic / remote code execution ---
    ("dynamic-exec", "high", rx(r"\beval\s*\("), "added"),
    ("dynamic-exec", "high", rx(r"\bexec\s*\("), "added"),
    ("dynamic-exec", "high", rx(r"\bnew\s+Function\s*\("), "added"),
    ("dynamic-exec", "high", rx(r"\bos\.system\s*\("), "added"),
    (
        "dynamic-exec",
        "high",
        rx(r"subprocess\.[A-Za-z_]+\([^)]*shell\s*=\s*True"),
        "added",
    ),
    ("dynamic-exec", "high", rx(r"child_process\.(exec|execSync|spawn)\s*\("), "added"),
    ("dynamic-exec", "high", rx(r"Runtime\.getRuntime\(\)\.exec\s*\("), "added"),
    ("dynamic-exec", "high", rx(r"\b(system|passthru|shell_exec|popen)\s*\("), "added"),
    # --- Reverse shells / socket-backed shells ---
    ("reverse-shell", "critical", rx(r"/dev/tcp/"), "added"),
    ("reverse-shell", "critical", rx(r"\bbash\s+-i\b"), "added"),
    ("reverse-shell", "critical", rx(r"\b(nc|ncat|netcat)\b[^\n]*\s-e\b"), "added"),
    ("reverse-shell", "critical", rx(r"\bsocat\b[^\n]*EXEC"), "added"),
    ("reverse-shell", "high", rx(r"\bmkfifo\b"), "added"),
    ("reverse-shell", "high", rx(r"dup2\s*\([^)]*(0|1|2)\s*\)"), "added"),
    # --- Download-and-execute ---
    ("download-exec", "high", rx(r"\b(curl|wget)\b[^\n|]*\|\s*(ba)?sh\b"), "added"),
    (
        "download-exec",
        "high",
        rx(
            r"\b(curl|wget|Invoke-WebRequest|iwr)\b[^\n]*(-o|-O|>)[^\n]*\.(sh|ps1|py|exe)\b",
        ),
        "added",
    ),
    # --- Tunnels / proxies / C2 / beaconing ---
    ("tunnel-c2", "high", rx(r"\bssh\b[^\n]*\s-[RLD]\b"), "added"),
    (
        "tunnel-c2",
        "high",
        rx(r"\b(ngrok|cloudflared|localtunnel|frpc|chisel|gost|autossh)\b"),
        "added",
    ),
    ("tunnel-c2", "high", rx(r"\b169\.254\.169\.254\b"), "added"),  # cloud metadata
    (
        "tunnel-c2",
        "high",
        rx(
            r"https?://(discord(app)?\.com/api/webhooks|hooks\.slack\.com|api\.telegram\.org|pastebin\.com|paste\.ee|transfer\.sh|requestbin)"
        ),
        "added",
    ),
    (
        "tunnel-c2",
        "medium",
        re.compile(r"https?://\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}"),
        "added",
    ),  # raw-IP URL (triage)
    # --- TLS / signature verification disabled ---
    (
        "crypto-weakened",
        "high",
        rx(
            r"(verify\s*=\s*False|rejectUnauthorized\s*:\s*false|InsecureSkipVerify\s*:\s*true|verify_signature\s*[:=]\s*(false|False)|CURLOPT_SSL_VERIFY(PEER|HOST)\s*,\s*(0|false))"
        ),
        "added",
    ),
    (
        "crypto-weakened",
        "high",
        rx(r"(algorithm|alg)\s*[:=]\s*['\"]?none['\"]?"),
        "added",
    ),
    ("crypto-weakened", "medium", rx(r"\b(MD5|SHA1)\b"), "added"),
    # --- IaC / cloud / K8s exposure & privilege ---
    ("iac-exposure", "high", re.compile(r"0\.0\.0\.0/0|::/0"), "added"),
    ("iac-exposure", "high", rx(r"\"?(Action|Principal)\"?\s*:\s*\"?\*\"?"), "added"),
    ("iac-exposure", "high", rx(r"publicly_accessible\s*=\s*true"), "added"),
    (
        "iac-exposure",
        "high",
        rx(
            r"(hostNetwork|hostPID|hostIPC|privileged|allowPrivilegeEscalation)\s*:\s*true",
        ),
        "added",
    ),
    ("iac-exposure", "high", rx(r"runAsNonRoot\s*:\s*false"), "added"),
    ("iac-exposure", "medium", rx(r"\b(NodePort|cluster-admin)\b"), "added"),
    (
        "iac-exposure",
        "high",
        rx(r"capabilities[^\n]*\b(SYS_ADMIN|NET_ADMIN|NET_RAW)\b"),
        "added",
    ),
    ("iac-exposure", "high", rx(r"docker\.sock"), "added"),
    # --- CI secret exposure / exfiltration ---
    (
        "ci-secret-exposure",
        "high",
        rx(r"(echo|printenv|env\b|cat|curl|wget)[^\n]*\$\{\{\s*secrets\."),
        "added",
    ),
    (
        "ci-secret-exposure",
        "high",
        rx(r"\$\{\{\s*secrets\.[^\n]*(curl|wget|http|\bnc\b|>|\|)"),
        "added",
    ),
    (
        "ci-secret-exposure",
        "medium",
        rx(r"permissions\s*:\s*write-all|pull_request_target"),
        "added",
    ),
    # --- Supply chain: install scripts, suspect dep sources ---
    ("supply-chain", "high", rx(r"\"(preinstall|postinstall|install)\"\s*:"), "added"),
    (
        "supply-chain",
        "high",
        rx(r"[:=]\s*['\"]?(git\+https?|github:|git://)"),
        "added",
    ),  # dep from git URL
    (
        "supply-chain",
        "medium",
        rx(r"--(extra-)?index-url|--trusted-host|GOPROXY|registry\s*="),
        "added",
    ),
    # --- Money-math heuristics (rounding / float-for-money / skim constants) ---
    (
        "money-math",
        "medium",
        rx(
            r"\b(math\.floor|Math\.floor|math\.trunc|Math\.trunc)\s*\([^)]*(amount|price|fee|interest|premium|balance|total|payout|commission)"
        ),
        "added",
    ),
    (
        "money-math",
        "medium",
        rx(
            r"\b(int|float|Number)\s*\([^)]*(amount|price|fee|interest|premium|balance|payout)",
        ),
        "added",
    ),
    (
        "money-math",
        "medium",
        rx(r"(amount|price|fee|total|balance|premium)\s*[-+*]\s*0\.\d{1,4}\b"),
        "added",
    ),
    ("money-math", "medium", rx(r"\b(remainder|residual|dust|rounding)\b"), "added"),
    # --- Targeted / conditional diversion & logic bombs ---
    (
        "targeted-logic",
        "high",
        rx(
            r"\bif\b[^\n]*(user_?id|account|customer_?id|email)\s*(==|===|\bin\b)\s*['\"\(\{\[]",
        ),
        "added",
    ),
    (
        "targeted-logic",
        "medium",
        rx(
            r"\bif\b[^\n]*(datetime|date|now|today|time)\b[^\n]*(>=?|<=?|==)[^\n]*20\d\d",
        ),
        "added",
    ),
    (
        "logic-bomb-env",
        "medium",
        rx(
            r"\b(CI|GITHUB_ACTIONS|BUILDKITE|PYTEST_CURRENT_TEST|JENKINS)\b[^\n]*(==|!=|in\b)",
        ),
        "added",
    ),
    # --- Obfuscation / encoded-then-executed ---
    (
        "obfuscation",
        "high",
        rx(r"\b(eval|exec)\s*\(\s*(atob|base64|b64decode|Buffer\.from)"),
        "added",
    ),
    ("obfuscation", "high", rx(r"new\s+Function\s*\(\s*(atob|Buffer\.from)"), "added"),
    (
        "obfuscation",
        "medium",
        rx(
            r"(String\.fromCharCode|fromCharCode|\\x[0-9a-fA-F]{2}(\\x[0-9a-fA-F]{2}){6,})",
        ),
        "added",
    ),
    # --- Insecure deserialization ---
    (
        "deserialization",
        "high",
        rx(
            r"\b(pickle\.loads|yaml\.load\s*\((?![^)]*Loader)|Marshal\.load|unserialize\s*\(|BinaryFormatter|readObject\s*\()"
        ),
        "added",
    ),
    # --- Anti-forensics / failing open (scope: removed or both) ---
    (
        "anti-forensics",
        "high",
        rx(r"(audit|security|payment|auth|fraud)[^\n]*\b(log|logger|logging)\b"),
        "removed",
    ),
    (
        "anti-forensics",
        "medium",
        rx(r"except\s*:\s*pass|catch\s*\([^)]*\)\s*\{\s*\}"),
        "added",
    ),
    (
        "auth-control-removed",
        "high",
        rx(
            r"\b(authenticate|authorize|authorise|verify|check_permission|require_auth|has_role|is_admin|csrf|signature|sanction|screen|kyc)\b"
        ),
        "removed",
    ),
]

# Filenames/paths that are inherently elevated-risk (reported as context leads).
HIGH_RISK_PATH = rx(
    r"(payment|billing|ledger|settlement|payout|refund|invoice|fee|interest|premium|"
    r"commission|fx|currency|wallet|treasury|"
    r"auth|session|rbac|permission|sign|token|"
    r"aml|kyc|sanction|fraud|monitor|"
    r"terraform|/k8s/|/helm/|\.github/workflows|\.buildkite|dockerfile|"
    r"package(-lock)?\.json|requirements.*\.txt|go\.(mod|sum)|pom\.xml|\.npmrc|migrations?/)"
)

# Names that, combined with high entropy, suggest a real secret value.
SECRET_NAME = rx(
    r"(password|passwd|pwd|secret|api[_-]?key|access[_-]?key|private[_-]?key|client[_-]?secret|token|credential)"
)

# This skill's own directory, in both its deployed (.claude/skills/...) and
# physical (skills/...) path forms. The catalogues and the DETECTORS table above
# deliberately contain illustrative wallet/eval/reverse-shell patterns; leads in
# these files are self-referential examples, not live indicators, and must not
# feed the mechanical Critical/High -> BLOCK gate (nor be "fixed" downstream).
SELF_SKILL_PATH = re.compile(r"^(\.claude/)?skills/zego-audit-financial-integrity/")


@dataclass
class Lead:
    file: str
    line: int
    change: str  # "added" | "removed"
    category: str
    severity_hint: str
    pattern: str
    snippet: str
    # lead is in this skill's own files (catalogue/detector example)
    self_referential: bool = False


def shannon_entropy(s: str) -> float:
    if not s:
        return 0.0
    freq = {c: s.count(c) for c in set(s)}
    n = len(s)
    return -sum((c / n) * math.log2(c / n) for c in freq.values())


def luhn_ok(num: str) -> bool:
    digits = [int(d) for d in num if d.isdigit()]
    if not (13 <= len(digits) <= 19):
        return False
    checksum, parity = 0, len(digits) % 2
    for i, d in enumerate(digits):
        if i % 2 == parity:
            d *= 2
            if d > 9:
                d -= 9
        checksum += d
    return checksum % 10 == 0


def _header_path(raw: str, strip_prefix: str) -> str | None:
    """Parse the path from a unified-diff '--- '/'+++ ' file header.

    Returns ``None`` for the ``/dev/null`` sentinel (file add/delete), otherwise
    the path with its ``a/``/``b/`` prefix stripped.
    """
    p = raw[4:].strip()
    if p == "/dev/null":
        return None
    return p[2:] if p.startswith(strip_prefix) else p


def _hunk_start(raw: str, old_no: int, new_no: int) -> tuple[int, int]:
    """Parse a ``@@ -old +new @@`` hunk header into its starting line numbers.

    Falls back to the current ``(old_no, new_no)`` when the header is malformed,
    so the caller never has to branch on a failed match.
    """
    m = re.search(r"-(\d+)(?:,\d+)?\s+\+(\d+)(?:,\d+)?", raw)
    if m:
        return int(m.group(1)), int(m.group(2))
    return old_no, new_no


@dataclass
class _DiffState:
    """Mutable cursor for the unified-diff state machine in ``iter_diff_lines``."""

    cur: str | None = None
    old_path: str | None = None
    old_no: int = 0
    new_no: int = 0
    in_hunk: bool = False


def _consume_structural(state: _DiffState, raw: str) -> bool:
    """Handle the ``diff --git`` reset and ``@@`` hunk header; True if consumed."""
    if raw.startswith("diff --git"):
        state.in_hunk = False
        state.cur = None
        return True
    if raw.startswith("@@"):
        state.in_hunk = True
        state.old_no, state.new_no = _hunk_start(raw, state.old_no, state.new_no)
        return True
    return False


def _consume_file_header(state: _DiffState, raw: str) -> bool:
    """Handle ``--- ``/``+++ `` file headers (only before the first ``@@``).

    Once inside a hunk these are content (e.g. a removed ``---`` frontmatter line
    arriving as ``----``), so they must fall through to the +/- branches. On a
    whole-file deletion the new path is ``/dev/null``; fall back to the old path
    so removed-control lines are still attributed and scanned.
    """
    if state.in_hunk:
        return False
    if raw.startswith("--- "):
        state.old_path = _header_path(raw, "a/")
        return True
    if raw.startswith("+++ "):
        new_path = _header_path(raw, "b/")
        state.cur = new_path if new_path is not None else state.old_path
        return True
    return False


def _emit(state: _DiffState, cur: str, raw: str) -> DiffLine | None:
    """Classify a content line, advancing the line counters; the +/- line or None."""
    if raw.startswith("+"):
        out: DiffLine = (cur, state.new_no, "added", raw[1:])
        state.new_no += 1
        return out
    if raw.startswith("-"):
        out = (cur, state.old_no, "removed", raw[1:])
        state.old_no += 1
        return out
    if raw.startswith("\\"):  # e.g. "\ No newline at end of file" — not a content line
        return None
    state.old_no += 1  # context line
    state.new_no += 1
    return None


def iter_diff_lines(diff_text: str) -> Iterator[DiffLine]:
    """Yield (filepath, new_lineno|old_lineno, change, raw_line) for +/- lines."""
    state = _DiffState()
    for raw in diff_text.splitlines():
        if _consume_structural(state, raw) or _consume_file_header(state, raw):
            continue
        if state.cur is None:
            continue
        emitted = _emit(state, state.cur, raw)
        if emitted is not None:
            yield emitted


def _secret_is_noise(content: str) -> bool:
    """A ``secret`` detector hit that is a low-entropy or placeholder value."""
    val = re.search(r"['\"]([^'\"]{8,})['\"]", content)
    if not val:
        return False
    if shannon_entropy(val.group(1)) < 3.0 and not SECRET_NAME.search(content):
        return True
    return bool(
        re.search(
            r"(example|changeme|placeholder|dummy|xxxx|your[_-]?|test_)",
            val.group(1),
            re.I,
        )
    )


def _is_noise(
    category: str,
    pattern: re.Pattern[str],
    m: re.Match[str],
    content: str,
) -> bool:
    """Suppress obvious false positives per detector category."""
    hit = m.group(0)
    if (
        category == "crypto-wallet"
        and pattern.pattern.startswith(r"\b0x")
        and "0x0000000000" in hit
    ):
        return True
    if (
        category == "financial-identifier"
        and m.re.pattern.startswith(r"\b\d{2}-\d{2}-\d{2}")
        and re.search(r"\d{4}-\d\d-\d\d", content)
    ):
        return True  # looks like a date, not a sort code
    if category == "secret" and "[:=]" in pattern.pattern:
        return _secret_is_noise(content)
    return False


def _detector_leads(
    path: str,
    lineno: int,
    change: str,
    content: str,
    stripped: str,
) -> list[Lead]:
    """Run every catalogue detector against one diff line, minus obvious noise."""
    leads: list[Lead] = []
    for category, sev, pattern, scope in DETECTORS:
        if scope != "both" and scope != change:
            continue
        m = pattern.search(content)
        if not m or _is_noise(category, pattern, m, content):
            continue
        leads.append(
            Lead(path, lineno, change, category, sev, m.group(0)[:80], stripped[:200]),
        )
    return leads


def _luhn_leads(
    path: str,
    lineno: int,
    change: str,
    content: str,
    stripped: str,
) -> list[Lead]:
    """At most one card-number (Luhn) lead per added line."""
    if change != "added":
        return []
    for cand in re.findall(r"\b(?:\d[ -]?){13,19}\b", content):
        if luhn_ok(cand):
            return [
                Lead(
                    path,
                    lineno,
                    "added",
                    "card-number-luhn",
                    "critical",
                    "possible PAN (passes Luhn)",
                    stripped[:200],
                )
            ]
    return []


def _elevated_path_leads(seen_files: set[str]) -> list[Lead]:
    """One context lead per file that sits on a money/auth/infra/dependency path."""
    leads: list[Lead] = []
    for f in sorted(seen_files):
        if f and HIGH_RISK_PATH.search(f):
            leads.append(
                Lead(
                    f,
                    0,
                    "n/a",
                    "elevated-risk-path",
                    "info",
                    "file in a money/auth/infra/dependency path",
                    f,
                )
            )
    return leads


def _mark_self_referential(leads: list[Lead]) -> None:
    """Flag leads in this skill's own files and cap them at ``info``.

    The catalogues' example patterns must stay visible but can never drive a
    BLOCK verdict. The intent-level question for such a diff (does it weaken
    detection?) is for the reviewing model, not a regex.
    """
    for lead in leads:
        if SELF_SKILL_PATH.search(lead.file):
            lead.self_referential = True
            lead.severity_hint = "info"


def scan(diff_text: str) -> list[Lead]:
    leads: list[Lead] = []
    seen_files: set[str] = set()
    for path, lineno, change, content in iter_diff_lines(diff_text):
        seen_files.add(path)
        stripped = content.strip()
        if not stripped:
            continue
        leads.extend(_detector_leads(path, lineno, change, content, stripped))
        leads.extend(_luhn_leads(path, lineno, change, content, stripped))
    leads.extend(_elevated_path_leads(seen_files))
    _mark_self_referential(leads)
    return leads


# Dependency manifests / lockfiles worth handing to a vulnerability scanner.
MANIFEST_NAMES = (
    "package.json",
    "package-lock.json",
    "yarn.lock",
    "pnpm-lock.yaml",
    "requirements.txt",
    "Pipfile.lock",
    "poetry.lock",
    "go.mod",
    "go.sum",
    "pom.xml",
    "build.gradle",
    "Gemfile.lock",
    "composer.lock",
    "Cargo.lock",
)


def _run_gitleaks(diff_text: str) -> list[dict[str, Any]]:
    """gitleaks: scan only the diff content via stdin (no repo history walk)."""
    if not shutil.which("gitleaks"):
        return []
    try:
        r = subprocess.run(
            [
                "gitleaks",
                "stdin",
                "--no-banner",
                "--report-format",
                "json",
                "--report-path",
                "/dev/stdout",
            ],
            input=diff_text,
            capture_output=True,
            text=True,
            timeout=120,
        )
    except Exception as e:  # noqa: BLE001
        return [{"tool": "gitleaks", "error": str(e)}]
    if r.stdout.strip():
        return [{"tool": "gitleaks", "scope": "diff", "raw": r.stdout[:20000]}]
    return []


def _run_osv_scanner(changed_files: list[str]) -> list[dict[str, Any]]:
    """osv-scanner: only the changed manifests/lockfiles, not the whole tree."""
    manifests = [f for f in changed_files if f and f.rsplit("/")[-1] in MANIFEST_NAMES]
    if not (manifests and shutil.which("osv-scanner")):
        return []
    cmd = ["osv-scanner", "--format", "json"]
    for m in manifests:
        cmd += ["--lockfile", m]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    except Exception as e:  # noqa: BLE001
        return [{"tool": "osv-scanner", "error": str(e)}]
    if r.stdout.strip():
        return [
            {
                "tool": "osv-scanner",
                "scope": "changed-manifests",
                "manifests": manifests,
                "raw": r.stdout[:20000],
            }
        ]
    return []


def run_external_tools(
    diff_text: str,
    changed_files: list[str],
) -> list[dict[str, Any]]:
    """Best-effort: fold in findings from common scanners if installed.

    Scoped to the change under review, NOT the whole repo or git history:
    gitleaks scans only the diff (piped on stdin, no git), and osv-scanner is
    run only against changed dependency manifests/lockfiles. This keeps findings
    on-target for a diff-scoped review and avoids full-history timeouts.
    """
    return _run_gitleaks(diff_text) + _run_osv_scanner(changed_files)


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Deterministic pre-scan for financial code integrity review."
    )
    ap.add_argument(
        "--diff",
        required=True,
        help="Path to a unified diff, or '-' for stdin.",
    )
    ap.add_argument(
        "--repo",
        default=".",
        help="Repo root (for optional external tools).",
    )
    ap.add_argument("--out", default="-", help="Output JSON path, or '-' for stdout.")
    ap.add_argument(
        "--no-external",
        action="store_true",
        help="Skip external scanners.",
    )
    args = ap.parse_args()

    diff_text = (
        sys.stdin.read()
        if args.diff == "-"
        else open(args.diff, encoding="utf-8", errors="replace").read()
    )

    leads = scan(diff_text)
    changed_files = sorted({f for f, _, _, _ in iter_diff_lines(diff_text)})
    sev_order = {"critical": 0, "high": 1, "medium": 2, "info": 3}
    leads.sort(
        key=lambda lead: (sev_order.get(lead.severity_hint, 9), lead.file, lead.line),
    )

    result: dict[str, Any] = {
        "summary": {
            "total_leads": len(leads),
            "by_category": {
                c: sum(1 for lead in leads if lead.category == c)
                for c in sorted({lead.category for lead in leads})
            },
            "by_severity_hint": {
                s: sum(1 for lead in leads if lead.severity_hint == s)
                for s in sorted({lead.severity_hint for lead in leads})
            },
        },
        "note": "Leads are starting points, NOT verdicts. Confirm/dismiss each with reasoning using the reference catalogues. Removed-line leads (deleted controls) matter as much as added ones.",
        "leads": [asdict(lead) for lead in leads],
        "external_tools": (
            [] if args.no_external else run_external_tools(diff_text, changed_files)
        ),
    }
    text = json.dumps(result, indent=2)
    if args.out == "-":
        print(text)
    else:
        with open(args.out, "w", encoding="utf-8") as f:
            f.write(text)
        print(f"Wrote {len(leads)} leads to {args.out}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
