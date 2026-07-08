# Secrets, Customer Data, PII/PCI & Exfiltration

Read for changes touching secrets/config, customer or account data, logging,
test fixtures/seed data, or any outbound data flow.

## Contents
1. Hardcoded secrets, keys & tokens
2. Customer/account/card data where it shouldn't be (incl. staging & fixtures)
3. Data exfiltration to external destinations
4. Sensitive data in logs, errors & URLs
5. Weakened data protection (encryption, masking, redaction)
6. What to ask for

---

## 1. Hardcoded secrets, keys & tokens

**Malicious / suspect shapes**
- Live credentials committed in code/config/CI/IaC: API keys, OAuth client
  secrets, DB connection strings with passwords, private keys
  (`-----BEGIN ... PRIVATE KEY-----`), cloud keys (`AKIA…`, GCP/Azure keys), SaaS
  tokens (Stripe `sk_live_…`, GitHub `ghp_…`/`gho_…`, Slack `xox…`, JWTs),
  webhook signing secrets, encryption keys/IVs.
- High-entropy strings assigned to names like `secret`, `token`, `key`, `password`,
  `passwd`, `apikey`, `auth`, `credential`.
- A secret moved **out** of a secret manager / env into source ("for convenience").
- A *real* secret added to a `.env.example`, test, or fixture file.

**Benign to rule out:** obvious placeholders (`xxxx`, `changeme`, `example`,
`dummy`, `test_…`), well-known non-secret test keys (e.g. Stripe's published test
keys), and references to secrets (`os.environ["X"]`, `${{ secrets.X }}`) rather
than the secret value itself.
**Check:** Is any committed string an actual live secret (high entropy, real
prefix, plausibly valid)? Did a secret move from managed storage into the repo? If
plausibly live → **Critical**, and note it must be rotated regardless of outcome.
Maps to OWASP A02:2025 / A04:2025, CWE-798/CWE-321; PCI DSS Req 3/8; the secret
must be treated as compromised once in Git history.

## 2. Customer/account/card data where it shouldn't be (incl. staging & fixtures)

Your specific concern: real account/customer details landing in non-production or
in code.

**Malicious / suspect shapes**
- Real **PANs** (card numbers — 13–19 digits passing Luhn), CVV/CVC, full track
  data, expiry; real IBANs/sort codes/account numbers; real National Insurance
  numbers, passport/driving-licence numbers, DOBs, full names + addresses tied to
  real people — in source, seed data, test fixtures, snapshots, or sample payloads.
- A **production data dump** (a `.sql`/`.csv`/`.json` of real customer rows) added
  to the repo or to a staging seed.
- Staging/test config pointed at the **production database** or pulling real PII.
- Storage of **Sensitive Authentication Data** (CVV, full track, PIN) at all —
  prohibited after authorization under PCI DSS Req 3; flag any code path that
  persists it.
- Full PAN stored unmasked where it should be truncated/tokenised (PCI: mask to
  first6/last4, render PAN unreadable in storage).

**Benign to rule out:** synthetic/fake data generators (Faker), the standard test
PANs published by card schemes (`4242 4242 4242 4242` etc.), and clearly fictional
fixtures.
**Check:** Does any added data look like **real** people's financial/identity data
rather than synthetic? Does any non-prod config touch prod data? Is SAD ever
stored, or full PAN stored unmasked? Real customer/card data in the repo or in
staging → **Critical** (data-protection + PCI exposure; UK GDPR/DPA implications).
Maps to PCI DSS Req 3 (protect stored account data), Req 3.3 (no SAD post-auth);
OWASP A04:2025; CWE-312 (Cleartext Storage), CWE-359 (Privacy Exposure).

## 3. Data exfiltration to external destinations

**Malicious / suspect shapes**
- Customer/account/secret data sent to an **external or unexpected** URL, webhook,
  email, S3 bucket, message queue, pastebin, Discord/Telegram/Slack webhook, or
  analytics endpoint that isn't an established dependency.
- A new outbound call that includes sensitive fields in the body/headers/query.
- Environment/credential reconnaissance: reading many env vars / files / cloud
  metadata (`169.254.169.254`) and posting them out (classic dependency-confusion
  payload behaviour).
- Bulk export/scan of a customer table feeding an outbound sink.
- Data encoded (base64/hex/gzip) right before being sent out (obfuscating the
  exfil).

**Benign to rule out:** sending data to your *own* documented services/telemetry;
partner integrations that match a ticket and an allowlist.
**Check:** Trace sensitive data to every outbound sink — is each destination an
established, documented, allowlisted endpoint? Does anything read env/secrets/
metadata and send it off-box? Maps to MITRE ATT&CK T1041/T1567 (Exfiltration),
T1552 (Unsecured Credentials); OWASP A02:2025; PCI DSS Req 4 (protect data in
transit).

## 4. Sensitive data in logs, errors & URLs

**Malicious / suspect shapes**
- Logging full PAN/CVV, passwords, tokens, secrets, full PII, or entire request/
  response bodies containing them.
- Putting sensitive data in **URLs/query strings** (logged by proxies, leaked in
  referrers) instead of bodies/headers.
- Verbose error/stack traces exposing secrets or internal data to clients.
- Removing an existing **masking/redaction** filter so previously-hidden data now
  appears in logs.

**Check:** Does the change cause sensitive data to be logged, placed in a URL, or
exposed in errors? Did any redaction/masking get weakened or removed? Maps to
CWE-532 (Info Exposure Through Logs), CWE-598 (Info in Query String); PCI DSS Req
3.3 (don't log SAD); OWASP A09:2025.

## 5. Weakened data protection (encryption, masking, redaction)

**Malicious / suspect shapes**
- Encryption removed or downgraded for data at rest/in transit (e.g. TLS
  verification disabled, TLS 1.0/1.1 allowed — PCI requires TLS 1.2+; cipher
  weakened; ECB mode; hardcoded IV/key; switching a strong hash to MD5/SHA-1 for a
  security purpose).
- Tokenisation/masking bypassed so raw values flow/persist.
- A field's classification quietly changed so it's no longer protected.

**Check:** Does the change weaken how sensitive data is encrypted, masked,
tokenised, or transmitted? Maps to OWASP A04:2025 (Cryptographic Failures),
CWE-327/CWE-326; PCI DSS Req 3 & 4.

## 6. What to ask for ("how to confirm benign")

Confirmation that any committed credential is a placeholder or already-public test
key (and if not, that it has been rotated); that any added data is synthetic, not
real customer/card data; that non-prod environments never touch production data;
that every outbound destination handling sensitive data is documented and allow-
listed; and that masking/redaction/encryption controls are intact or strengthened,
not reduced.
