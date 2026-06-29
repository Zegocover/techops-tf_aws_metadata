# Financial Integrity — money manipulation & skimming catalogue

The most important reference in this skill. Read it for **any** change touching
amounts, balances, fees, interest, premiums, payouts, refunds, ledgers, FX,
commissions, or beneficiary/account details.

For each technique: the idea, what the **malicious** code tends to look like, how
to tell it from a **legitimate** change, and what to check. Patterns are
illustrative across languages — reason about behaviour, not exact syntax.

## Contents
1. Rounding / truncation skimming ("salami slicing")
2. Beneficiary & destination-account diversion
3. Fee, commission & spread manipulation
4. Interest, APR & premium tampering
5. Floating-point money handling
6. Sign, overflow & boundary tricks
7. Ledger / double-entry & reconciliation abuse
8. Refund, void, chargeback & adjustment abuse
9. Test-mode / sandbox logic reaching production
10. Conditional / targeted diversion (logic gated on identity)
11. Currency, unit & scale confusion
12. Duplicate, replay & race-condition value creation
13. Unapplied cash, suspense & dormant-account sweeping
14. Discounts, vouchers, cashback & loyalty abuse
15. Tax / withholding redirection
16. Disabling or weakening financial-crime controls (AML / sanctions / monitoring)
17. Quiet limit, threshold & approval-gate changes
18. Cross-cutting tells & what to ask for

---

## 1. Rounding / truncation skimming ("salami slicing")

The classic. Money calculations to fractional units leave a remainder; the fraud
diverts the rounded-off slice — imperceptible per transaction, large in aggregate
across millions of transactions. Commonly hidden in interest, payroll, billing,
FX, and any per-line proration.

**Malicious / suspect shapes**
- Switching a calculation from round-half-even/round-half-up to **truncate toward
  zero** (`math.floor`, `int()`, `Math.trunc`, integer division) on customer
  credits — and crediting the difference elsewhere.
- A "remainder", "residual", "dust", "adjustment", or "rounding" amount that is
  computed and then **assigned to a fixed account** rather than returned to the
  customer or a controlled rounding ledger.
- Inconsistent rounding: debit the customer rounded *up*, credit them rounded
  *down*, and book the gap.
- A new constant subtracted "for rounding" (`amount - 0.01`, `* 0.9999`).

```python
# SUSPECT: remainder of a proration quietly routed to a hardcoded account
total_cents = principal * rate // 1
per_item = total_cents // n
remainder = total_cents - per_item * n
credit(items, per_item)
credit_account("acct_9981", remainder)   # <-- where does this go, and why?
```

**Benign explanation to rule out:** rounding remainders legitimately need a home;
mature systems book them to a *named, reconciled* "rounding differences" GL
account, documented and configurable — not a hardcoded personal/opaque account.
**Check:** Where does the residual go? Is the destination configurable and
reconciled, or fixed in code? Did rounding *direction* change for credits vs
debits? Is there a new "remainder/dust" sink?

## 2. Beneficiary & destination-account diversion

The payout/transfer recipient is altered or overridden.

**Malicious / suspect shapes**
- A **hardcoded** IBAN, sort code + account number, card token, PAN, wallet, or
  payment-rail destination in payout/settlement/refund code (vs sourced from the
  verified payee record).
- An **override**: `recipient = payee.account` followed by a conditional that
  replaces it (`if X: recipient = "GB..."`).
- Beneficiary read from an **untrusted or attacker-controllable** source (a
  header, a request body field, an env var newly introduced) instead of the
  stored, validated mandate.
- A "fallback" recipient used when the real one is missing/empty — pointing
  somewhere fixed.
- Last-octet / last-digit mutation of an account number (looks like a typo fix).

**Benign explanation to rule out:** test fixtures legitimately contain fake
accounts; legitimate config holds the firm's *own* treasury/clearing account
(ideally in a managed secret, allowlisted).
**Check:** Is any real-money destination hardcoded or overridable at runtime by
input? Trace the recipient from source to the payment call — is every hop trusted?

## 3. Fee, commission & spread manipulation

Skimming via the firm's own fee/commission/markup logic.

**Malicious / suspect shapes**
- An **extra** fee/markup added on top of the legitimate one and booked to a
  different account.
- Commission rate or split nudged (e.g. `0.015` → `0.0155`), or a new recipient
  added to a split.
- An FX rate marked up beyond the documented spread, or a second hidden spread
  applied.
- Fee computed on a larger base than disclosed (gross vs net), or applied twice.
- A "service"/"processing"/"handling" fee introduced with no product/ticket
  backing.

**Check:** Does the change introduce or alter any fee/commission/markup? Does the
math match documented pricing? Are fee destinations the expected GL accounts?

## 4. Interest, APR & premium tampering

For lending and insurance specifically.

**Malicious / suspect shapes**
- Interest accrual rounding changed (links to §1), or day-count/convention
  switched to favour one side.
- APR/premium formula altered so the customer-facing figure and the charged figure
  diverge.
- A small constant added to every premium/instalment, swept to an account.
- Late-fee/penalty logic that triggers more readily or compounds where it
  shouldn't.

**Check:** Compare the quoted/displayed value path against the charged/accrued
value path — do they compute the same number? Any new constants or convention
changes in accrual?

## 5. Floating-point money handling

Money in binary floating point silently loses precision; differences can be
harvested, and it is also a reckless-integrity smell that can mask deliberate
skimming.

**Malicious / suspect shapes**
- Money represented or computed as `float`/`double` (JS `number`) where the
  codebase otherwise uses integer minor units or fixed-point `Decimal`/`BigDecimal`.
- Casting `Decimal` → `float` mid-calculation, then rounding.
- Accumulating money in a `float` loop.

**Benign explanation to rule out:** a `float` used for a *non-monetary* ratio,
score, or display metric is fine.
**Check:** Is this value actually money? Does it deviate from the repo's money
type? Where does the lost precision go?

## 6. Sign, overflow & boundary tricks

**Malicious / suspect shapes**
- A negative amount accepted where only positive is valid, flipping a debit into a
  credit (a "refund" of a negative, a transfer of a negative).
- Integer overflow/underflow on amount fields (esp. fixed-width ints) used to wrap
  a balance to a huge or negative value.
- `abs()` quietly applied to an amount that should retain its sign, or a sign
  inverted (`-amount`).
- Off-by-one in an instalment/amortisation schedule that drops or adds a payment.

**Check:** Are amount signs validated? Can a crafted negative/oversized value
produce value out of nothing? Did any sign or `abs` change?

## 7. Ledger / double-entry & reconciliation abuse

The books must balance; fraud breaks or hides the imbalance.

**Malicious / suspect shapes**
- A transaction posted with a debit but no matching credit (or vice versa), or to
  a wrong/opaque counter-account.
- An entry written **outside** the normal posting path (a raw SQL `INSERT`/
  `UPDATE` to a balances/ledger table, bypassing the service that enforces
  double-entry and audit).
- Reconciliation/variance checks weakened so an imbalance won't be flagged
  (raising a tolerance, skipping an assertion, swallowing an exception).
- A balance set directly rather than derived from movements.

**Check:** Does every posting balance? Is the canonical, audited posting path used,
or is it bypassed? Were any reconciliation tolerances/assertions changed?

## 8. Refund, void, chargeback & adjustment abuse

**Malicious / suspect shapes**
- Refund issued without a matching original charge, or for more than the original.
- Refund destination ≠ original payment source (money sent elsewhere).
- Void/reversal that releases funds without reversing the corresponding
  receivable.
- Manual "adjustment"/"goodwill credit" path with no authorisation gate or audit.
- Idempotency removed so a refund can be replayed.

**Check:** Is the refund bounded by, and routed to, the original payment? Is there
an approval/audit gate? Could it be triggered repeatedly?

## 9. Test-mode / sandbox logic reaching production

Real money moved through code that was meant to be a no-op or stub in production.

**Malicious / suspect shapes**
- A `test`/`sandbox`/`dry_run`/`simulate` branch that, in production config,
  actually executes real transfers — or whose guard was inverted/removed.
- Pointing the live payment client at a sandbox endpoint (or vice versa) via a
  changed base URL/flag.
- A mock/stub that now returns "success" for real charges, or auto-approves.
- `if not PRODUCTION:` guards removed from money-moving code.

**Check:** Do environment guards correctly separate test from real money in
*production* config? Did any such guard change, invert, or disappear?

## 10. Conditional / targeted diversion (logic gated on identity)

The most deliberate fraud: behave normally except for specific
accounts/users/dates.

**Malicious / suspect shapes**
- `if user_id in {...}` / `if account == "..."` / `if email.endswith("...")`
  branches in money or auth paths that grant special treatment, skip fees, inflate
  credits, or redirect funds.
- Date/time-gated behaviour (`if today > 2026-12-01:`) — a logic bomb (see
  crypto-obfuscation §logic bombs).
- A "feature flag" or config key that, when set, changes who gets paid.

**Check:** Any branch keyed on a *specific* identity, account, date, or magic
value that alters financial outcome or access? Who chose that value, and why?

## 11. Currency, unit & scale confusion

**Malicious / suspect shapes**
- Mixing minor and major units (cents vs pounds) so a `× 100` / `÷ 100` lands in
  the fraudster's favour, or is dropped.
- Treating all currencies as 2-decimal (breaks JPY 0-decimal, etc.) to shave or
  inflate amounts.
- Hardcoded FX rate or a stale/again-favourable rate source.

**Check:** Are units consistent end to end? Is currency scale handled per-currency?
Is the FX source trusted and current?

## 12. Duplicate, replay & race-condition value creation

**Malicious / suspect shapes**
- Idempotency keys removed/weakened so a credit/refund/transfer can be submitted
  twice.
- A check-then-act on balance without locking (TOCTOU) enabling double-spend or
  overdraft.
- Retry logic that re-posts a successful payment.

**Check:** Is idempotency preserved? Are balance mutations atomic/locked? Can a
retry or race create money?

## 13. Unapplied cash, suspense & dormant-account sweeping

**Malicious / suspect shapes**
- Logic that sweeps unmatched/suspense/unapplied balances, or dormant-account
  funds, to a fixed destination.
- "Cleanup"/"reconcile"/"sweep" jobs that move customer money out without an
  audited, reversible, owned process.
- Write-off thresholds raised so balances are written off (and captured) more
  readily.

**Check:** Does anything move residual/suspense/dormant funds? To where, with what
authorisation and audit trail?

## 14. Discounts, vouchers, cashback & loyalty abuse

**Malicious / suspect shapes**
- Discount/voucher/cashback that can stack or exceed the charge, or be self-issued
  without limits.
- A promo code branch granting outsized or uncapped value, gated on a magic code.
- Loyalty-point → cash conversion altered in the user's favour or self-redeemable.

**Check:** Are credits capped and bounded by the transaction? Any self-serviceable
or magic-code value grant?

## 15. Tax / withholding redirection

**Malicious / suspect shapes**
- Withheld tax/levy directed to a non-authority account (cf. the classic payroll-
  withholding salami fraud).
- Tax computed but quietly not remitted, the amount captured elsewhere.

**Check:** Do tax/withholding amounts flow to the correct authority destination?

## 16. Disabling or weakening financial-crime controls (AML / sanctions / monitoring)

Tampering with controls is itself nefarious in a regulated firm, and enables
laundering/sanctions evasion (MLR 2017, POCA, UK sanctions; see
`regulatory-and-standards.md`).

**Malicious / suspect shapes**
- Sanctions/PEP **screening bypassed or short-circuited** (an early `return True`,
  a screen call commented out, a hardcoded "clear" result, an allowlist that
  swallows everyone).
- Transaction-monitoring rules disabled, thresholds raised so nothing alerts, or
  alerts suppressed/auto-closed.
- KYC/CDD checks skipped for certain customers, or verification auto-passed.
- SAR/alert generation disabled or its trigger neutered.
- Fuzzy-match thresholds loosened so sanctioned names never match.

**Check:** Does the change touch any screening/monitoring/KYC/SAR logic? Does it
reduce coverage, raise thresholds, suppress alerts, or hardcode a "pass"? Even a
plausibly-performance-motivated change here is High+ until justified.

## 17. Quiet limit, threshold & approval-gate changes

**Malicious / suspect shapes**
- Transaction/payout/withdrawal limits raised, or a maker-checker / dual-approval
  gate removed or bypassed for money movement.
- An approval requirement made conditional on a magic value so the fraudster's
  path skips it.
- Velocity/anti-fraud limits loosened.

**Check:** Were any monetary limits, approval gates, or segregation-of-duties
controls weakened, removed, or made bypassable?

## 18. Cross-cutting tells & what to ask for

**Tells that elevate any of the above:**
- The change to money/control logic is **not explained** by the PR description or
  ticket (intent-vs-implementation gap).
- A **hardcoded** account/recipient/rate/threshold of any kind in a money path.
- A new value sink (account, address, URL, env var) introduced alongside the math.
- A money path that **bypasses** the canonical, audited service in favour of raw
  DB writes or a direct API call.
- Removal of validation, idempotency, reconciliation, or audit around money.
- Anything keyed on a *specific* identity, magic code, or date.

**What to ask the author to show (put in "how to confirm benign"):** the ticket/
spec justifying the change; where any residual/fee/tax lands and that it is a
named, reconciled account; that recipients/rates/thresholds come from trusted,
validated config or records (not input or hardcode); that env/test guards still
separate real money in production; and that audit and reconciliation remain intact.
