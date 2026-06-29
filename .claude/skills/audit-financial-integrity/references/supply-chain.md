# Software Supply Chain

Read for changes to dependency manifests/lockfiles, CI/CD config, build scripts,
or vendored third-party code. Supply-chain attack is now its own OWASP category
(A03:2025) and is one of the most common ways malicious code enters a financial
system without an insider writing it directly.

## Contents
1. Dependency additions & changes
2. Install / lifecycle scripts
3. Typosquatting
4. Dependency confusion
5. Lockfile / manifest integrity
6. CI/CD & build pipeline poisoning
7. What to ask for & useful tooling

---

## 1. Dependency additions & changes

**Malicious / suspect shapes**
- A **new top-level dependency added in a change whose purpose doesn't need it**
  (a one-line bugfix that also adds a package) — strong intent-vs-implementation
  signal.
- A package that is **very recently published**, has **few downloads**, a **single
  unknown maintainer**, **no source repository link**, or a name that mimics a
  popular package.
- A dependency repointed from the registry to a **git URL, tarball URL, or a fork**
  (`"pkg": "git+https://…"`, `github:user/repo`, a `file:`/`http(s):` source).
- A version pinned to an exact patch that is **newer than/just released** for an
  otherwise-stable package (possible compromised release), or an unpinned/`*`/
  `latest` range introduced for a sensitive package.
- A transitive dependency suddenly overridden/resolved to an unusual source.

**Benign to rule out:** a dependency genuinely required by the feature, from a
well-known maintainer/registry, pinned sensibly; routine bumps that match a
changelog.
**Check:** Is each added/changed dependency necessary for the stated change, from a
trusted source, and not mimicking another package? Maps to OWASP A03:2025; CWE-1357
(reliance on insufficiently trustworthy component).

## 2. Install / lifecycle scripts

Install-time scripts execute arbitrary code on developer laptops and CI runners
with no sandbox — a primary supply-chain payload vector.

**Malicious / suspect shapes**
- A `preinstall`/`postinstall`/`install` script added in `package.json` (or
  setup hooks in `setup.py`/`pyproject`, gem extensions, Go `//go:generate`, Maven
  plugins) — especially one that downloads a payload, runs a shell command, reads
  env vars, writes to temp and spawns a detached process, or contacts a network
  host.
- A `scripts/postinstall.js` (or similar) that is obfuscated, base64-decoded, or
  fetches remote code (`curl | sh`, `https GET` then exec) — the documented
  dependency-confusion / npm-worm pattern.
- A build/setup step that exfiltrates environment/credentials during install.

**Check:** Does the change add or modify any install/build lifecycle script? Read
exactly what it does on each run; decode anything encoded. New install scripts that
touch network, env, or the filesystem outside the build dir → High+. Maps to OWASP
A03:2025; MITRE ATT&CK T1195 (Supply Chain Compromise), T1059.

## 3. Typosquatting

**Malicious / suspect shapes**
- A dependency name that is a near-miss of a popular one (transposed letters,
  added/removed char, hyphen/underscore swap, `-js`/`.js` suffix, look-alike
  scope), e.g. resembling `react`, `lodash`, `requests`, `colors`, `chalk`.
- A package impersonating an internal/known tool's name.

**Check:** Does any package name closely resemble a well-known or internal package
but isn't it? Cross-check the exact name and publisher.

## 4. Dependency confusion

An attacker publishes a **public** package with the same name as one of your
**private/internal** packages; misconfigured resolution pulls the malicious public
one.

**Malicious / suspect shapes**
- A scoped/internal name (`@yourorg/…` or an internal package) that now resolves to
  the **public** registry rather than your private feed.
- Registry/resolution config changed (`.npmrc`, `pip.conf`/`--extra-index-url`,
  `.pypirc`, Maven `repositories`, `go env GOPROXY`) to add a public source for
  internal names, or to lower private-feed precedence.
- A new public package whose name matches an internal service/namespace (attackers
  mirror real corporate scopes).

**Check:** Could any internal package now be satisfied from a public registry? Did
registry precedence/scoping change? Maps to OWASP A03:2025; treat as High+ (OpenSSF
classifies dependency-confusion packages as malicious by default).

## 5. Lockfile / manifest integrity

**Malicious / suspect shapes**
- A **lockfile changed without a corresponding manifest change** (or vice versa),
  or a lockfile resolving a package to an **unexpected URL/integrity hash**.
- Integrity hashes removed/altered; `--no-verify`/integrity checks disabled.
- A lockfile entry whose `resolved` URL points off the official registry.
- A huge lockfile churn buried in an unrelated PR (hiding one malicious resolution
  among many).

**Check:** Do manifest and lockfile agree? Do resolved URLs/integrity hashes point
to the official registry and match expectations? Investigate lockfile-only changes.

## 6. CI/CD & build pipeline poisoning

The pipeline often holds the most powerful credentials; compromising it is high
-impact (OWASP A03:2025/A08:2025; OWASP CI/CD Top 10).

**Malicious / suspect shapes (GitHub Actions / Buildkite / general)**
- A workflow/pipeline step running an **unpinned third-party action** (`uses:
  someone/action@main` instead of a pinned commit SHA), or a newly-added action
  from an unknown publisher.
- A step that **exfiltrates secrets**: echoing/curling `${{ secrets.* }}`, env, or
  the CI token to an external host; printing the environment; uploading artifacts
  to an unexpected destination.
- `pull_request_target` / elevated-permission triggers combined with running
  untrusted PR code; broad `permissions:` (e.g. `write-all`); self-hosted-runner
  jobs triggered by forks.
- `curl | bash` / download-and-run in a build step; adding an unknown package
  source or signing key; disabling signature/provenance/SBOM checks.
- Buildkite: a new hook or `command` step that fetches remote scripts, reads agent
  secrets/env and sends them out, or alters the agent's network/trust.
- Changing deployment/promotion steps to skip approvals, sign with a different key,
  or push to an unexpected registry/environment.
- Modifying release/publish steps to add an extra artifact or destination.

**Check:** Does any CI change run untrusted code, expand permissions/triggers,
expose secrets/tokens, or weaken build provenance/approvals? Pin and verify; treat
secret-exposing or trigger-broadening changes as High+. Maps to OWASP A03:2025 &
A08:2025; MITRE ATT&CK T1195.

## 7. What to ask for & useful tooling

**Ask for:** the reason each dependency/CI change is needed for the stated work;
the source, maintainer, and provenance of new dependencies; confirmation that
internal names resolve only to the private feed; that lockfile changes match the
manifest and resolve to the official registry; and that CI secrets are never
printed/exported and third-party actions are pinned by digest.

**Tooling the pre-scan will use if present (otherwise note as a recommendation):**
`osv-scanner`/`trivy` (cross-reference the **OpenSSF malicious-packages** database
and CVEs), `npm audit signatures`/provenance, `socket`-style behavioural checks,
and SBOM generation (CycloneDX/SPDX) with SLSA provenance for release artifacts.
