---
version: 1.0
last_reviewed: 2026-05-11
---

# Protobuf Converter Standards

Conventions for converting between Python types and Zego protobuf message types — the governing philosophy is never hand-roll a conversion; always use `zego.protobuf.converters`, and if a converter is missing, add it to the `zego-protobuf` package rather than writing inline conversion code. Apply these rules whenever writing or modifying code that constructs, reads, or converts any `zego.protobuf.*` or `google.protobuf.*` message type. Python language conventions are owned by `docs/ai/steering/languages/python.md`.

## Rules at a Glance

1. **No hand-rolled conversions.** Always use `zego.protobuf.converters` for any proto type in the reference table below — hand-rolled implementations consistently get sign-matched nanos wrong (corrupting `FixedDecimal`), treat epoch as a real date rather than "absent" (corrupting `Timestamp` and `Date`), and silently apply the wrong rounding mode (corrupting `Money`).
2. **Nullability suffix.** Use `from_X` / `to_X` when the value is guaranteed non-`None`; use `from_X_optional` / `to_X_optional` when the value or its proto "unset" sentinel may represent absence — the `_optional` variants translate the proto3 zero-value sentinel to `None` automatically so callers never need to know the sentinel.
3. **Proto3 zero-values mean absent.** `Timestamp(seconds=0)`, `Date(year=0, month=0, day=0)`, an empty `Url.url`, and any `*_UNSPECIFIED = 0` enum member all signal "not set" in proto3; use `_optional` variants to handle this transparently — passing these sentinels through non-optional converters returns incorrect results.
4. **`MoneyConverter.to_integer` for minor-unit APIs only.** Use it only for Stripe-style APIs that expect amounts in the smallest currency unit; it truncates with `ROUND_DOWN` and the round-trip is intentionally lossy — there is no `from_integer`.
5. **`EnumConverter` as a module-level constant.** Construct `EnumConverter` once at module level and reuse it — instantiation introspects `DESCRIPTOR.values` to strip prefixes and is wasteful per-call.
6. **UUID direct construction.** There is no `UUIDConverter`; construct `zego.protobuf.UUID` directly as `UUID(uuid=str(my_python_uuid))` — the proto contract requires lowercase, hyphenated form and `str(uuid.UUID(...))` already produces it.
7. **Go upstream for missing converters.** If a proto type has no converter in `zego.protobuf.converters`, add one to the `zego-protobuf` package rather than hand-rolling in service code — putting the converter in the package ensures correctness invariants are shared and tested once.

## Converter Reference Table

| Proto type | Python type | Converter |
|---|---|---|
| `zego.protobuf.FixedDecimal` | `decimal.Decimal` | `FixedDecimalConverter` |
| `zego.protobuf.Money` | `(Decimal, currency_code)` or minor-unit `int` | `MoneyConverter` |
| `google.protobuf.Timestamp` | `datetime.datetime` | `TimestampConverter` |
| `zego.protobuf.Date` | `datetime.date` | `DateConverter` |
| `zego.protobuf.Url` | `str` | `UrlConverter` |
| Any proto enum | A native Python `Enum` | `EnumConverter` |
| `zego.protobuf.UUID` | `str` | None — construct directly (see Rule 6) |

All converters import from `zego.protobuf.converters`.

## No hand-rolled conversions

`FixedDecimal` stores an amount as `sint64 units` and `sfixed32 nanos`, and `units` and `nanos` must have matching signs (or one must be zero). A hand-rolled implementation that sets `nanos` from the fractional part of an absolute value will produce incorrect results for negative amounts: `-1.75` must be `units=-1, nanos=-750_000_000`, not `units=-1, nanos=750_000_000`. `FixedDecimalConverter` enforces this invariant.

`Timestamp` and `Date` use proto3 defaults (seconds=0, all-zero date fields) to represent "not set". A hand-rolled `to_datetime` that does not account for this will return the Unix epoch rather than `None`, corrupting any downstream code that treats `None` as absent.

`MoneyConverter` truncates with `ROUND_DOWN` for minor-unit conversion; a reimplementation that uses `ROUND_HALF_UP` or `ROUND_HALF_EVEN` will produce values one unit too high, leading to overcharging.

```python
from decimal import Decimal
from zego.protobuf.converters import FixedDecimalConverter

# good
fd = FixedDecimalConverter.from_decimal(Decimal("-1.75"))
# → FixedDecimal(units=-1, nanos=-750_000_000) — signs matched

# bad — hand-rolled; sign of nanos is wrong for negative amounts
fd = FixedDecimal(units=-1, nanos=750_000_000)  # invalid; to_decimal raises ValueError
```

## Nullability suffix

Every converter ships two pairs of methods. Use the right pair for the nullability of your input:

- `from_X(value)` — value is non-`None`; raises `TypeError` or `ValueError` on `None` or the proto zero-value.
- `from_X_optional(value)` — value may be `None`; returns the proto zero-value sentinel when given `None`.
- `to_X(proto)` — proto field is non-`None` and not a zero-value sentinel; returns the Python type.
- `to_X_optional(proto)` — proto field may be `None` or the zero-value sentinel; returns `None` in those cases.

```python
from datetime import date
from zego.protobuf.converters import DateConverter

# good — optional variant when the date may be absent
proto_date = DateConverter.from_date_optional(None)   # → Date(year=0, month=0, day=0)
python_date = DateConverter.to_date_optional(proto_date)  # → None

# bad — non-optional variant when the value may be None
proto_date = DateConverter.from_date(None)            # raises TypeError
```

## Proto3 zero-values mean absent

Proto3 cannot distinguish between a field that was never set and a field explicitly set to its zero value. Zego's convention is that the zero value always means "not set":

- `Timestamp(seconds=0, nanos=0)` → absent datetime
- `Date(year=0, month=0, day=0)` → absent date
- `Url(url="")` → absent URL
- Any `*_UNSPECIFIED = 0` enum member → absent enum value

Use `_optional` converter variants to get `None` for these cases automatically. Use the non-optional variants only when you have verified the field was explicitly set to a meaningful value.

```python
from zego.protobuf.converters import TimestampConverter

# good — optional variant handles the epoch-as-absent convention
dt = TimestampConverter.to_datetime_optional(ts_field)  # None if ts_field is epoch

# bad — non-optional variant; returns epoch datetime when field was never set
dt = TimestampConverter.to_datetime(ts_field)           # returns 1970-01-01T00:00:00Z
```

## `MoneyConverter.to_integer` for minor-unit APIs only

`to_integer` multiplies a `Money` amount by a unit multiplier and truncates with `ROUND_DOWN`. This is intentional: when a calculated amount cannot be represented exactly (e.g. £10.999), charging the customer one minor unit less is preferable to charging one too many. The round-trip is lossy by design.

Use `to_integer` only when the downstream API (e.g. Stripe) requires amounts in the smallest currency unit. Do not use it for display, persistence, or arithmetic.

There is no `from_integer`. If you need one, add it to the `zego-protobuf` package with explicit rounding semantics documented.

```python
from zego.protobuf.converters import MoneyConverter

# good — Stripe charge in pence
amount_pence, currency = MoneyConverter.to_integer(money)         # default multiplier=100
amount_yen, _ = MoneyConverter.to_integer(jpy_money, multiplier=1)  # zero-decimal currency

# bad — using to_integer for a stored amount; loses sub-pence precision permanently
stored_amount = MoneyConverter.to_integer(money)[0]
```

## `EnumConverter` as a module-level constant

`EnumConverter` introspects the proto enum's `DESCRIPTOR.values` on construction to determine the longest common prefix to strip. This introspection is not free — done per-call inside a handler or service method it adds unnecessary work on every invocation. Construct once at module level.

The Python `Enum` does not need an `UNSPECIFIED` member. The converter maps the proto's zero-value `_UNSPECIFIED` member to `None` automatically.

```python
from enum import Enum
from zego.protobuf.accounts.v1.phonenumber_pb2 import PhoneNumber
from zego.protobuf.converters import EnumConverter

class PhoneNumberLabel(Enum):
    MOBILE = "mobile"
    HOME = "home"

# good — constructed once at module level
PHONE_LABEL = EnumConverter(PhoneNumberLabel, PhoneNumber.PhoneNumberLabel)

PHONE_LABEL.to_enum(PhoneNumber.PHONE_NUMBER_LABEL_MOBILE)          # PhoneNumberLabel.MOBILE
PHONE_LABEL.to_enum(PhoneNumber.PHONE_NUMBER_LABEL_UNSPECIFIED)     # None
PHONE_LABEL.from_enum_optional(None)                                # PHONE_NUMBER_LABEL_UNSPECIFIED

# bad — reconstructed inside a function; pays introspection cost per call
def convert_label(proto_label: int) -> PhoneNumberLabel | None:
    converter = EnumConverter(PhoneNumberLabel, PhoneNumber.PhoneNumberLabel)
    return converter.to_enum(proto_label)
```

## UUID direct construction

`zego.protobuf.UUID` is `{ string uuid = 1; }` — a thin wrapper around a string. No converter is needed. Construct it directly using `str(my_python_uuid)`, which always produces lowercase, hyphenated form (e.g. `3403768f-898a-4dd4-854a-b1f1e63a0fc2`). Do not uppercase it; the proto contract requires lowercase.

```python
import uuid
from zego.protobuf.uuid_pb2 import UUID

# good
proto_uuid = UUID(uuid=str(my_python_uuid))         # lowercase, hyphenated
python_uuid = uuid.UUID(proto_uuid.uuid)

# bad — uppercase form violates the proto contract
proto_uuid = UUID(uuid=str(my_python_uuid).upper())
```

## Go upstream for missing converters

If a proto type in `zego.protobuf.*` or `google.protobuf.*` has no converter in `zego.protobuf.converters`, the correct response is to add one to the `zego-protobuf` package — not to write inline conversion logic in service code. Service-local conversions embed correctness invariants in a place where they cannot be tested centrally, are not shared, and are invisible to other teams working with the same type.

Before adding a converter, check whether one already exists in the package. If the converter you need does not exist, add it to the `zego-protobuf` package with tests, then import and use it.

## See Also

- [../languages/python.md](../languages/python.md) — Python conventions: project structure, dependency injection, typing, and functional core/imperative shell.
