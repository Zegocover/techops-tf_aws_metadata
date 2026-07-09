#!/usr/bin/env bash
# feature-id.sh — the shared, allowlisted feature-identifier utility.
#
# A feature identifier is a Jira-independent, what-three-words-style token of
# the form `word-word-word-hex4`, e.g. `quartz-amber-ronin-7e67`. It is minted
# once at the first PR-producing skill of a feature, persisted in artefact
# frontmatter, and recovered + reused by every later skill so that the
# requirement, design, and implementation PRs of one feature carry one shared
# key. See docs/design/AIDEV-188-value-stream-artefact-linking.md.
#
# Usage:
#   .claude/scripts/feature-id.sh mint
#   .claude/scripts/feature-id.sh validate <candidate>
#   .claude/scripts/feature-id.sh recover <artefact-path>
#   .claude/scripts/feature-id.sh decide <recovered-id-or-empty> <predecessor-pr-exists:true|false>
#
# Subcommands:
#   mint
#     Reads the vendored wordlist (feature-id.words.txt, a sibling of this
#     script) and asserts W >= 7000 — failing loud on a truncated or corrupted
#     list rather than silently shrinking the keyspace — then draws the three
#     word indices AND the hex4 suffix from /dev/urandom (via `openssl rand`),
#     never bash $RANDOM (15-bit, modulo-biased against a 7,776-word list).
#     Prints one identifier to stdout; exit 0.
#
#   validate <candidate>
#     Exit 0 if the candidate matches the identifier regex; exit 1 if malformed
#     or Jira-key-shaped. No stdout.
#
#   recover <artefact-path>
#     Prints the first identifier-shaped token found on a `feature-?id` label
#     line (matched truly case-insensitively, so `Feature-Id`, `feature-id`,
#     and `FEATURE-ID` all match). Format-agnostic across the requirements
#     metadata-table row, the design-doc header line, and the task-spec YAML
#     key. Empty stdout + exit 1 if absent or malformed.
#
#   decide <recovered-id-or-empty> <predecessor-pr-exists:true|false>
#     The Open-Q2 mint-vs-recover-vs-lost rule. Prints exactly one of:
#       REUSE <id>   — a valid id was recovered (regardless of predecessor PR)
#       LOST         — no valid id, but a predecessor PR exists
#       MINT         — no valid id and no predecessor PR
#     Exit 0 on valid input.
#
# Why this script vs inline shell:
#   - One allowlist entry covers the whole "mint / validate / recover / decide a
#     feature identifier" intent across every PR-producing skill.
#   - The wordlist integrity assertion and the /dev/urandom entropy source live
#     in one place, not duplicated per caller.
#
# Best-effort, never blocks (caller contract):
#   - Skills treat mint / recover failures as warnings and proceed; a reporting
#     gap is acceptable, a blocked skill is not. This script itself returns the
#     documented exit codes; the best-effort downgrade lives in the callers.
#
# Exit codes:
#   0  success (subcommand output on stdout where documented)
#   1  recover: no valid identifier found in the artefact;
#      validate: the candidate is malformed or Jira-key-shaped
#   2  malformed or missing subcommand arguments, or a non-existent file
#   *  mint only: non-zero when /dev/urandom is unavailable or the wordlist is
#      missing / shorter than 7,000 words

set -uo pipefail

# The canonical identifier shape: three lowercase-alpha words then a 4-hex
# suffix, hyphen-separated. Anchored so a Jira-key-shaped string (AIDEV-188)
# and any partial match are rejected.
readonly FEATURE_ID_REGEX='^[a-z]+-[a-z]+-[a-z]+-[0-9a-f]{4}$'

# Minimum acceptable wordlist size. The vendored EFF large diceware list is
# 7,776 words; this floor fails loud on a truncated / corrupted list rather
# than drawing tokens from a shrunken keyspace.
readonly MIN_WORDLIST_SIZE=7000

# Resolve the vendored wordlist as a sibling of this script, following the
# script's own symlink so it works whether invoked via the symlinked
# deployment path or the physical source path.
feature_id_wordlist_path() {
  local src="${BASH_SOURCE[0]}"
  local dir
  dir="$(cd "$(dirname "$src")" && pwd -P)"
  printf '%s/feature-id.words.txt\n' "$dir"
}

# Draw a uniform random non-negative integer in [0, bound) from /dev/urandom
# via `openssl rand`. Rejection sampling on 4 bytes (uint32) eliminates the
# modulo bias that a bare `% bound` would introduce. Never uses $RANDOM.
# Echoes the integer on stdout; non-zero exit if the entropy source fails.
feature_id_rand_below() {
  local bound="$1"
  local limit raw value
  # Largest multiple of bound that fits in a uint32; values at or above this
  # are rejected so the kept range is an exact multiple of bound (unbiased).
  limit=$(( (4294967295 / bound) * bound ))
  while :; do
    # 4 bytes from /dev/urandom, rendered as 8 hex digits, parsed base-16.
    raw="$(openssl rand -hex 4 2>/dev/null)" || return 1
    [ -n "$raw" ] || return 1
    value=$(( 16#$raw ))
    if (( value < limit )); then
      printf '%s\n' "$(( value % bound ))"
      return 0
    fi
  done
}

# Print one random word from the wordlist file given its size W. Reads the
# 1-based line at a uniformly-random index via sed.
feature_id_random_word() {
  local wordlist="$1" size="$2"
  local idx
  idx="$(feature_id_rand_below "$size")" || return 1
  # sed line addressing is 1-based; the drawn index is 0-based.
  sed -n "$(( idx + 1 ))p" "$wordlist"
}

cmd_mint() {
  local wordlist size
  wordlist="$(feature_id_wordlist_path)"

  if [[ ! -f "$wordlist" ]]; then
    echo "feature-id: wordlist '$wordlist' not found; cannot mint" >&2
    return 3
  fi

  # Count words. A blank/short line would still count, but the conformance of
  # the committed file is the vendoring contract; the floor guards truncation.
  size="$(LC_ALL=C grep -cE '^[a-z]+$' "$wordlist")"
  if (( size < MIN_WORDLIST_SIZE )); then
    echo "feature-id: wordlist '$wordlist' has $size words (< $MIN_WORDLIST_SIZE); refusing to mint from a shrunken keyspace" >&2
    return 4
  fi

  local w1 w2 w3 hex
  w1="$(feature_id_random_word "$wordlist" "$size")" || { echo "feature-id: entropy source /dev/urandom unavailable; refusing to mint" >&2; return 5; }
  w2="$(feature_id_random_word "$wordlist" "$size")" || { echo "feature-id: entropy source /dev/urandom unavailable; refusing to mint" >&2; return 5; }
  w3="$(feature_id_random_word "$wordlist" "$size")" || { echo "feature-id: entropy source /dev/urandom unavailable; refusing to mint" >&2; return 5; }

  # 2 bytes from /dev/urandom => exactly 4 hex digits. openssl rand failing
  # (no entropy source) is a non-zero exit; treat it as a mint failure.
  hex="$(openssl rand -hex 2 2>/dev/null)" || { echo "feature-id: entropy source /dev/urandom unavailable; refusing to mint" >&2; return 5; }
  if [[ ! "$hex" =~ ^[0-9a-f]{4}$ ]]; then
    echo "feature-id: entropy source /dev/urandom unavailable; refusing to mint" >&2
    return 5
  fi

  printf '%s-%s-%s-%s\n' "$w1" "$w2" "$w3" "$hex"
}

cmd_validate() {
  if [[ $# -lt 1 ]]; then
    echo "feature-id: validate requires a candidate argument" >&2
    echo "usage: feature-id.sh validate <candidate>" >&2
    return 2
  fi
  local candidate="$1"
  if [[ "$candidate" =~ $FEATURE_ID_REGEX ]]; then
    return 0
  fi
  return 1
}

cmd_recover() {
  if [[ $# -lt 1 ]]; then
    echo "feature-id: recover requires an artefact-path argument" >&2
    echo "usage: feature-id.sh recover <artefact-path>" >&2
    return 2
  fi
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "feature-id: artefact '$path' not found" >&2
    return 2
  fi

  # Find every `feature-?id` label line, truly case-insensitively (so an
  # all-caps FEATURE-ID also matches — not the partial fold
  # [Ff]eature-?[Ii]d). On each such line, extract the first token matching
  # the identifier regex and print it. Stop at the first hit.
  local line token
  while IFS= read -r line; do
    # Pull out the first word-word-word-hex4 token on the line.
    token="$(printf '%s\n' "$line" | grep -oE '[a-z]+-[a-z]+-[a-z]+-[0-9a-f]{4}' | head -1)"
    if [[ -n "$token" ]] && [[ "$token" =~ $FEATURE_ID_REGEX ]]; then
      printf '%s\n' "$token"
      return 0
    fi
  done < <(grep -iE 'feature-?id' "$path")

  # No identifier-shaped token on any feature-id label line.
  return 1
}

cmd_decide() {
  if [[ $# -lt 2 ]]; then
    echo "feature-id: decide requires <recovered-id-or-empty> <predecessor-pr-exists:true|false>" >&2
    echo "usage: feature-id.sh decide <recovered-id-or-empty> <true|false>" >&2
    return 2
  fi
  local recovered="$1" predecessor="$2"

  if [[ "$predecessor" != "true" && "$predecessor" != "false" ]]; then
    echo "feature-id: decide predecessor-pr-exists must be 'true' or 'false', got '$predecessor'" >&2
    return 2
  fi

  # A valid recovered id always reuses, regardless of whether a predecessor PR
  # exists.
  if [[ -n "$recovered" ]] && [[ "$recovered" =~ $FEATURE_ID_REGEX ]]; then
    printf 'REUSE %s\n' "$recovered"
    return 0
  fi

  # No valid id. A predecessor PR existing means the id was lost in transit —
  # never silently re-mint (would split the feature into two unlinked threads,
  # breaking FR-02). Proceed without an id.
  if [[ "$predecessor" == "true" ]]; then
    printf 'LOST\n'
    return 0
  fi

  # No valid id and no predecessor PR: a genuine first run. Mint.
  printf 'MINT\n'
  return 0
}

feature_id_main() {
  if [[ $# -lt 1 ]]; then
    echo "feature-id: missing subcommand" >&2
    echo "usage: feature-id.sh <mint|validate|recover|decide> [args...]" >&2
    return 2
  fi
  local sub="$1"
  shift
  case "$sub" in
    mint)     cmd_mint "$@" ;;
    validate) cmd_validate "$@" ;;
    recover)  cmd_recover "$@" ;;
    decide)   cmd_decide "$@" ;;
    *)
      echo "feature-id: unknown subcommand '$sub'" >&2
      echo "usage: feature-id.sh <mint|validate|recover|decide> [args...]" >&2
      return 2
      ;;
  esac
}

# Run main only when executed directly, not when sourced (e.g. by unit tests).
# Source-guard: a sourced script must not run its main.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  feature_id_main "$@"
fi
