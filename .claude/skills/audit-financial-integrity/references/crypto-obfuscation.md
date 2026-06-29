# Cryptocurrency, Obfuscation & Logic Bombs

Read for hardcoded addresses, encoded/obfuscated content, dynamic code execution,
deserialization, or anything time/condition-gated.

## Contents
1. Cryptocurrency wallet addresses
2. Cryptominers
3. Obfuscation & encoded payloads
4. Dynamic code execution
5. Insecure deserialization
6. Logic bombs & time bombs

---

## 1. Cryptocurrency wallet addresses

A hardcoded wallet address in a financial system is a strong skim/diversion or
ransomware indicator — money can be moved to crypto irreversibly and
pseudonymously, and UK sanctions/AML rules apply to cryptoassets too.

**Address formats to recognise**
- **Bitcoin:** legacy P2PKH `1…` and P2SH `3…` (Base58, ~26–35 chars); bech32/
  bech32m SegWit `bc1…` (and testnet `tb1…`); taproot `bc1p…`.
- **Ethereum / EVM:** `0x` + 40 hex chars (also covers many L2s/ERC-20 contexts).
- **Litecoin:** `L…`/`M…`/`ltc1…`. **Bitcoin Cash:** `bitcoincash:q…`.
- **Monero:** `4…`/`8…`, ~95 chars (privacy coin — especially concerning).
- **Tron** `T…`, **Ripple/XRP** `r…`, **Solana** base58 ~32–44 chars,
  **Cosmos/ATOM** `cosmos1…`, **Dogecoin** `D…`.
- ENS/`.eth` names and `*.crypto` resolved at runtime to an address.
- Any of the above built/assembled at runtime, decoded from base64/hex, or read
  from a newly-added env/config value in a payout path.

**Benign to rule out:** a legitimate crypto product whose addresses are sourced
from verified user/payee records or vetted config — not hardcoded as a recipient.
A `0x…40hex` may also be a non-address hash; confirm by use (is it used as a
payment/transfer destination?). A `bc1…`-looking token in unrelated test data may
be a fixture.
**Check:** Is any crypto address present, and is it used as a **destination** for
value? Is it hardcoded/decoded/env-sourced rather than from a validated record? Any
hardcoded wallet in a money path → **Critical**. Maps to OWASP A08:2025; CWE-506;
UK sanctions/MLR 2017 (cryptoasset obligations); MITRE ATT&CK T1496 (Resource
Hijacking) when paired with mining.

## 2. Cryptominers

**Malicious / suspect shapes**
- Mining libraries/binaries or pool protocol use: `stratum+tcp://`, references to
  `xmrig`, `cpuminer`, `minerd`, `ethminer`, `nbminer`, coin pool domains.
- WebAssembly/JS miners (e.g. CoinHive-style) injected into a frontend.
- Code that downloads and runs a miner, or spins CPU/GPU on a schedule and connects
  to a pool.
- Stealthy resource use: throttled CPU burn, run-only-when-idle, hidden process.

**Check:** Any mining library, pool URL, or download-and-run of a mining binary?
Maps to MITRE ATT&CK T1496 (Resource Hijacking).

## 3. Obfuscation & encoded payloads

Obfuscation is a red flag in its own right: legitimate first-party code rarely
needs to hide what it does.

**Malicious / suspect shapes**
- Large **base64/hex/gzip/zlib** blobs in source or config, especially if later
  decoded and executed/written to disk.
- Heavily minified/encoded logic checked into source (not a build artifact);
  string arrays + index decoders; `eval(atob(...))`, `Function(atob(...))()`.
- Char-code/`\xNN`/`\uNNNN` string assembly to hide a URL, command, or address.
- ROT13/XOR/custom decoders applied to strings before use.
- Misleading names/comments that disguise behaviour ("cleanup", "telemetry",
  "healthcheck" that actually exfiltrates or executes).
- Homoglyph/unicode tricks (look-alike characters) or invisible/zero-width
  characters in identifiers or strings.

**Benign to rule out:** legitimately embedded binary assets (icons, certs,
fixtures) that are *not* executed; checked-in build outputs in clearly-marked dist
folders.
**Check:** Is there encoded/obfuscated content, and is it **decoded then executed,
written to disk, or used as a network destination/command**? If yes → treat as
High+ and decode it to see what it is. Maps to OWASP A08:2025; CWE-506/CWE-507.

## 4. Dynamic code execution

**Malicious / suspect shapes**
- `eval`/`exec`/`compile`, `Function(...)`, `setTimeout("string")`, `vm.runInContext`
  on **non-constant** input.
- Deserializing then invoking; reflection to call methods named by input;
  `getattr`/`__import__` on input-derived names.
- Loading code from a remote URL, a DB field, a request, or an env var at runtime.
- Template engines used in a way that allows server-side template injection.

**Benign to rule out:** constant, developer-authored expressions; well-sandboxed,
fixed plugin systems.
**Check:** Does the change execute code/commands derived from input, network, or
storage? Maps to OWASP A05:2025 (Injection), CWE-94/CWE-95.

## 5. Insecure deserialization

**Malicious / suspect shapes**
- Deserializing untrusted input with dangerous formats: Python `pickle`/`PyYAML
  yaml.load` (non-safe), Java native serialization/`ObjectInputStream`, Ruby
  `Marshal`, PHP `unserialize`, .NET `BinaryFormatter`, or insecure use of
  gadgets-prone libraries.
- Accepting serialized objects from clients/queues and reconstructing them.

**Check:** Is untrusted data deserialized with a format that can execute code or
instantiate arbitrary types? Maps to OWASP A08:2025 (Software/Data Integrity
Failures), CWE-502.

## 6. Logic bombs & time bombs

Code that lies dormant and triggers on a condition — date, count, presence/absence
of a value, or a specific identity.

**Malicious / suspect shapes**
- Behaviour gated on a **date/time** (`if now > 2026-12-01`, `if date == ...`), an
  **anniversary/uptime/counter**, or a **kill switch** ("if my account is
  disabled, then…").
- A branch that activates only when a magic flag/env/value is set, or only for a
  specific user/account (overlaps `financial-integrity.md` §10 and
  `access-and-backdoors.md` §1).
- Environment-sniffing: behaving benignly in CI/test but differently in production
  (checking for CI env vars, hostnames, debugger, sandbox artefacts) to evade
  review and dynamic analysis.
- Self-deletion or trace-cleanup after acting.

**Check:** Is any behaviour conditioned on a date, counter, magic value, specific
identity, or on *not* being in a test/CI environment? Decode what the triggered
branch does. Maps to CWE-511 (Logic/Time Bomb), CWE-506; MITRE ATT&CK T1480
(Execution Guardrails).
