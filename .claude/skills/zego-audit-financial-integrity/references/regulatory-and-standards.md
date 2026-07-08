# Regulatory & Standards Mapping

Use this to tag each finding with the standard(s) it breaches and to justify
severity. In a regulated UK financial firm, citing the relevant control turns a
"this looks dodgy" into an auditable, defensible finding. Versions below are
current as of mid-2026 — if in doubt, verify against the primary source.

## Contents
1. OWASP Top 10:2025
2. PCI DSS v4.0.1
3. FCA Handbook & guidance (SYSC, FCG, Consumer Duty, SM&CR, Principle 11)
4. UK financial-crime law (MLR 2017, POCA, Sanctions, JMLSG, FATF)
5. CWE — weakness IDs for tagging
6. MITRE ATT&CK — adversary techniques
7. Secure-development & supply-chain frameworks (NIST SSDF, SLSA, SBOM, OpenSSF, NCSC)
8. Quick finding → standard lookup

---

## 1. OWASP Top 10:2025

The current edition (released Nov 2025; supersedes 2021). Two new categories and
one consolidation are directly relevant to this skill.

- **A01:2025 — Broken Access Control** (still #1; now **includes SSRF**). Auth/
  authz bypass, privilege escalation, IDOR, missing function-level checks.
- **A02:2025 — Security Misconfiguration** (up from #5). Over-permissive network/
  cloud config, exposed services, disabled TLS verification, debug enabled.
- **A03:2025 — Software Supply Chain Failures** (**NEW**; expands "Vulnerable &
  Outdated Components"). Malicious packages, compromised maintainers, install-
  script malware, dependency confusion, poisoned build/CI.
- **A04:2025 — Cryptographic Failures.** Weak/missing encryption, hardcoded keys,
  weak hashing for security, plaintext sensitive data.
- **A05:2025 — Injection.** Command/SQL/code injection, SSTI, dynamic exec on
  untrusted input.
- **A06:2025 — Insecure Design.** Architectural weaknesses (e.g. missing maker-
  checker, no segregation of duties on money movement).
- **A07:2025 — Authentication Failures.** Weak session/credential/MFA handling,
  fail-open auth.
- **A08:2025 — Software or Data Integrity Failures.** Insecure deserialization,
  tampered updates/CI, unsigned/altered code and data, logic/data tampering.
- **A09:2025 — Security Logging & Alerting Failures.** Missing/disabled logging,
  no alerting, anti-forensics, suppressed audit.
- **A10:2025 — Mishandling of Exceptional Conditions** (**NEW**). Fail-open error
  handling, swallowed exceptions on security paths, inconsistent error behaviour.

Map most skimming/diversion logic to **A08** (integrity) and **A06** (insecure
design); backdoors to **A01/A07**; tunnels/exposure to **A02**; exec/injection to
**A05**; deps/CI to **A03**; secrets/crypto to **A04**; disabled logging to **A09**.

## 2. PCI DSS v4.0.1

Current version; in full force since **31 March 2025**. Applies if the codebase
stores, processes, or transmits cardholder data (CHD) or could affect the security
of the cardholder data environment (CDE).

- **Req 1** — network security controls; over-broad firewall/SG rules breach this.
- **Req 3** — protect stored account data. **Render PAN unreadable** (truncation/
  tokenisation/strong crypto); **never store Sensitive Authentication Data (CVV,
  full track, PIN) after authorization.** Real PAN/SAD in code/fixtures/logs is a
  direct violation.
- **Req 4** — strong cryptography for CHD in transit; **TLS 1.2+** required, TLS
  1.0/1.1 prohibited; disabling cert verification breaches this.
- **Req 5** — protect against malware (relevant to miners/embedded malware).
- **Req 6** — develop & maintain secure software; remediate critical vulns
  promptly; **6.4.3** requires payment-page scripts be authorised, inventoried, and
  integrity-checked (anti-skimming / Magecart).
- **Req 7 / 8** — least privilege & strong access control; MFA into the CDE.
- **Req 10** — log & monitor all access; **11.6.1** requires change/tamper-
  detection on payment pages.

## 3. FCA Handbook & guidance

The firm is accountable to the FCA; tie integrity findings to these where relevant.

- **SYSC (Senior Management Arrangements, Systems & Controls)** — firms must have
  effective systems and controls, including over change and segregation of duties.
  **SYSC 6** covers financial-crime systems & controls.
- **SYSC 15A — Operational Resilience** (in force since 31 March 2025; PS21/3). A
  change that could disrupt an **important business service** (e.g. a backdoor,
  sabotage, or a control that fails open) engages operational-resilience duties.
- **FCA Financial Crime Guide (FCG)** (updated by **PS24/17**, 2024) — expectations
  on financial-crime systems & controls, including transaction monitoring and
  sanctions. Weakening AML/sanctions/monitoring code maps here.
- **Consumer Duty (PRIN 2A)** — firms must act to deliver good outcomes and avoid
  foreseeable harm. Skimming, mis-charging, or fund diversion is direct consumer
  harm.
- **Principle 11 (Relations with regulators)** — material failures may be
  notifiable to the FCA; a confirmed integrity breach in production is the kind of
  thing that can trigger this.
- **Senior Managers & Certification Regime (SM&CR)** — individual accountability
  for systems and controls; this is **why a named human must own the merge
  decision** and why the tool advises rather than approves.

## 4. UK financial-crime law

Tampering with controls, or building diversion/laundering pathways, engages:

- **Money Laundering, Terrorist Financing and Transfer of Funds (Information on the
  Payer) Regulations 2017 (MLR 2017)** — risk-based AML controls: KYC/CDD, ongoing
  monitoring, record-keeping. Disabling/loosening these in code maps here.
- **Proceeds of Crime Act 2002 (POCA)** — SAR obligations to the NCA/UKFIU;
  disabling SAR/alert generation undermines these.
- **Sanctions and Anti-Money Laundering Act 2018 / OFSI sanctions regimes** —
  mandatory screening of customers and transactions against sanctions lists
  (including for cryptoassets). Bypassing/loosening sanctions or PEP screening, or
  loosening fuzzy-match thresholds, is a serious finding.
- **JMLSG Guidance / FATF Recommendations** — industry/international AML standards
  the firm's controls are expected to reflect.

## 5. CWE — weakness IDs for tagging

- **CWE-506** Embedded Malicious Code · **CWE-507** Trojan Horse · **CWE-511**
  Logic/Time Bomb · **CWE-512** Spyware.
- **CWE-798** Hard-coded Credentials · **CWE-321** Hard-coded Crypto Key ·
  **CWE-259** Hard-coded Password.
- **CWE-912** Hidden Functionality · **CWE-489** Active Debug Code.
- **CWE-94/CWE-95** Code Injection/Eval · **CWE-78** OS Command Injection ·
  **CWE-502** Insecure Deserialization.
- **CWE-287** Improper Authentication · **CWE-306** Missing Authentication ·
  **CWE-862/CWE-863** Missing/Incorrect Authorization · **CWE-732**
  Incorrect Permission Assignment.
- **CWE-312** Cleartext Storage of Sensitive Info · **CWE-319** Cleartext
  Transmission · **CWE-532** Info Exposure Through Logs · **CWE-598** Info in Query
  String · **CWE-359** Privacy Exposure.
- **CWE-327/CWE-326** Broken/Weak Crypto · **CWE-915** Improperly Controlled
  Modification (mass assignment) · **CWE-682** Incorrect Calculation (money math).

## 6. MITRE ATT&CK — adversary techniques

- **T1195** Supply Chain Compromise · **T1059** Command/Scripting Interpreter ·
  **T1505** Server Software Component (web shell).
- **T1071** Application-Layer C2 · **T1572** Protocol Tunneling · **T1090** Proxy ·
  **T1568** Dynamic Resolution.
- **T1041** Exfiltration Over C2 · **T1567** Exfiltration Over Web Service ·
  **T1552** Unsecured Credentials.
- **T1480** Execution Guardrails (env-keying/logic bombs) · **T1053** Scheduled
  Task/Job · **T1496** Resource Hijacking (mining) · **T1070** Indicator Removal
  (anti-forensics).

## 7. Secure-development & supply-chain frameworks

- **NIST SSDF (SP 800-218)** — secure software development practices; useful framing
  for "controls that should exist."
- **SLSA** — supply-chain levels for software artifacts (provenance, signed builds).
- **SBOM** (CycloneDX / SPDX) — know what's in the build; basis for malicious-
  package detection.
- **OpenSSF** — `malicious-packages` database (consumable via OSV), Scorecard,
  best-practices; the data source behind dependency checks.
- **OWASP ASVS** (verification requirements), **OWASP SCVS** (software component
  verification), **OWASP CI/CD Top 10** — deeper checklists if a finding needs
  fuller backing.
- **UK NCSC** — secure development & supply-chain guidance aligned to the above.

## 8. Quick finding → standard lookup

- Fund skimming / diversion / fee or rounding manipulation → OWASP A08/A06; CWE-682/
  CWE-506; FCA Consumer Duty + SYSC; (if it enables laundering) MLR 2017.
- Hardcoded crypto wallet in money path → OWASP A08; CWE-506; UK sanctions/MLR 2017.
- Real PAN/SAD or customer data in repo/staging/logs → PCI DSS Req 3 (& 3.3),
  Req 10; OWASP A04; CWE-312/CWE-532; UK GDPR/DPA 2018.
- Secrets committed → OWASP A02/A04; CWE-798; PCI DSS Req 3/8 (rotate immediately).
- Auth bypass / backdoor / magic endpoint → OWASP A01/A07; CWE-798/CWE-912/CWE-287;
  MITRE T1505.
- Reverse shell / exec on untrusted input → OWASP A05; CWE-78/CWE-94; MITRE
  T1059/T1071.
- Tunnel / proxy / C2 / wide egress → OWASP A02; MITRE T1572/T1090/T1071.
- Firewall/SG/IaC/K8s exposure or privilege escalation → OWASP A02; CWE-732; PCI
  DSS Req 1/7.
- Disabled/weakened logging or audit → OWASP A09; CWE-778; MITRE T1070; FCA audit
  expectations.
- Disabled/loosened AML / sanctions / monitoring / KYC / SAR → FCA FCG + SYSC 6;
  MLR 2017; POCA; Sanctions Act 2018.
- Malicious/suspicious dependency, install script, dependency confusion, CI
  poisoning → OWASP A03 (& A08); MITRE T1195; OpenSSF malicious-packages.
- Logic/time bomb, obfuscated payload, insecure deserialization → OWASP A08/A05;
  CWE-511/CWE-506/CWE-502; MITRE T1480.
