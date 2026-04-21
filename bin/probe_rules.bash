#!/usr/bin/env bash

# Usage: LANGUAGETOOL_USERNAME=... LANGUAGETOOL_API_KEY=... ./probe.bash
#
# Probes the hosted LanguageTool /v2/check API across all supported
# languages, against both anonymous and Premium tiers, and prints a
# classification summary showing which rule IDs the current vs. proposed
# isUnknownWordRule() predicate would catch as spell-check rules.
#
# ----------------------------------------------------------------------
# FILLING IN TEST SAMPLES
# ----------------------------------------------------------------------
# The SAMPLES array below has one entry per language code supported by
# ltex-ls-plus. Entries marked `PLACEHOLDER` need to be filled in with a
# short test sentence in the target language containing 2-4 deliberate
# misspellings.
#
# Two approaches work:
#
#   (a) Natural-sentence approach (preferred when the author reads the
#       language): write a normal sentence and corrupt 2-4 content words
#       with realistic typo patterns (doubled consonants, transposed
#       letters, dropped accents, missing diacritics).
#
#   (b) Dummy-suffix approach (fine for a quick uniform probe): pick one
#       valid real word in the language and append a 2-letter nonsense
#       suffix the spell-checker will reject.
#         - Latin-script: append `zx` (e.g. `Hauszx` for German)
#         - Cyrillic:     append `зх`
#         - Greek:        append `ξζ`
#         - Arabic / Persian: append letter pairs unusual at end of word
#         - Hebrew:       append `צק` or similar
#         - CJK:          write a real word followed by a clearly-invalid
#                         character combination
#         - Indic (Tamil, Khmer): similar — a dummy invalid consonant run
#
# The goal is to trigger at least one spell-check match so we can observe
# the rule ID. Whether it is a "smart" realistic typo or a dummy suffix
# does not matter for predicate design — only the rule IDs matter.
#
# Entries already filled (empirically verified): en-US, en-GB, de-DE,
# de-CH, pt-PT, pt-BR, fr, es, it, nl, pl-PL.
# ----------------------------------------------------------------------

URL="https://api.languagetoolplus.com/v2/check"

# Text blocks, referenced by SAMPLES below. Each should contain at least
# one unambiguous misspelling.
EN_TEXT="I recieved teh package yesterday and its contents were amazng."
DE_TEXT="Ich habe das Pakket geschtern bekomen und der Inhalt war erstaulich."
PT_TEXT="Ontem recebii o pakote mas o conteúdo estava estraggado."
FR_TEXT="J'ai reccu un pakett hier soir mais il était cassez."
ES_TEXT="Ayer resivi el paqete y estava sorpredido con el contenidoo."
IT_TEXT="Ieri ho ricevutto il pakko ma era rottoo."
NL_TEXT="Gistern ontfing ik het paket maar het was beshadigd."
PL_TEXT="Wczorajj dostałem paczkke a zawartość byłła zniszczonna."

# Language -> text. "PLACEHOLDER" means no sample yet; the probe will be
# skipped and flagged in the output. Replace with a real sentence to
# activate the probe.
SAMPLES=(
  # --- English family (regional variants) ---
  "en-US|$EN_TEXT"
  "en-GB|$EN_TEXT"
  "en|$EN_TEXT"
  "en-AU|$EN_TEXT"
  "en-CA|$EN_TEXT"
  "en-NZ|$EN_TEXT"
  "en-ZA|$EN_TEXT"

  # --- German family ---
  "de-DE|$DE_TEXT"
  "de-AT|$DE_TEXT"
  "de-CH|$DE_TEXT"
  "de|$DE_TEXT"
  "de-DE-x-simple-language|$DE_TEXT"

  # --- Romance family ---
  "fr|$FR_TEXT"
  "es|$ES_TEXT"
  "es-AR|$ES_TEXT"
  "it|$IT_TEXT"
  "pt|$PT_TEXT"
  "pt-PT|$PT_TEXT"
  "pt-BR|$PT_TEXT"
  "pt-AO|$PT_TEXT"
  "pt-MZ|$PT_TEXT"
  "ca-ES|PLACEHOLDER"
  "ca-ES-valencia|PLACEHOLDER"
  "gl-ES|PLACEHOLDER"
  "ro-RO|PLACEHOLDER"
  "ast-ES|PLACEHOLDER"

  # --- Germanic non-English ---
  "nl|$NL_TEXT"
  "nl-BE|$NL_TEXT"
  "sv|PLACEHOLDER"
  "da-DK|PLACEHOLDER"

  # --- Slavic (Latin script) ---
  "pl-PL|$PL_TEXT"
  "sk-SK|PLACEHOLDER"
  "sl-SI|PLACEHOLDER"

  # --- Slavic (Cyrillic script) ---
  "ru-RU|PLACEHOLDER"
  "uk-UA|PLACEHOLDER"
  "be-BY|PLACEHOLDER"

  # --- Celtic ---
  "br-FR|PLACEHOLDER"
  "ga-IE|PLACEHOLDER"

  # --- Other European ---
  "el-GR|PLACEHOLDER"
  "eo|PLACEHOLDER"

  # --- Non-European ---
  "ar|PLACEHOLDER"
  "fa|PLACEHOLDER"
  "zh-CN|PLACEHOLDER"
  "ja-JP|PLACEHOLDER"
  "km-KH|PLACEHOLDER"
  "ta-IN|PLACEHOLDER"
  "tl-PH|PLACEHOLDER"

  # --- Auto-detection canaries ---
  "auto|$EN_TEXT"
  "auto|$DE_TEXT"
)

# Parallel arrays for the per-probe summary (bash 3.2-compatible).
SUMMARY_KEYS=()
SUMMARY_VALUES=()

# Simulates the current isUnknownWordRule() predicate from
# LanguageToolRuleMatch.kt. Returns 0 when the rule ID is classified as
# a spell-check rule under current ltex-ls-plus.
is_current_unknown_word_rule() {
  case "$1" in
    MORFOLOGIK_*|HUNSPELL_*) return 0 ;;
    *_SPELLER_RULE|*_SPELLING_RULE) return 0 ;;
    MUZSKY_ROD_NEZIV_A|ZENSKY_ROD_A|STREDNY_ROD_A) return 0 ;;
    *) return 1 ;;
  esac
}

# Simulates the extended predicate shipped on the fix/isUnknownWordRule
# branch of ltex-ls-plus: current set + any rule ID containing ORTHOGRAPHY
# (catches QB_NEW_*_ORTHOGRAPHY_* and AI_*_ORTHOGRAPHY_*) or _SIMPLE_REPLACE_
# (catches ES_SIMPLE_REPLACE_* and siblings).
is_proposed_unknown_word_rule() {
  is_current_unknown_word_rule "$1" && return 0
  case "$1" in
    *ORTHOGRAPHY*|*_SIMPLE_REPLACE_*) return 0 ;;
  esac
  return 1
}

# probe <label> <language> <text> [extra curl args...]
probe() {
  local label="$1"; shift
  local language="$1"; shift
  local text="$1"; shift
  echo "=== $label ==="
  if [[ "$text" == "PLACEHOLDER" ]]; then
    echo "(skipped — no sample text yet)"
    SUMMARY_KEYS+=("$label")
    SUMMARY_VALUES+=("")
    echo
    return
  fi
  local -a args=(
    --data-urlencode "language=$language"
    --data-urlencode "text=$text"
  )
  # Seed auto-detection with a few variants — LT requires a region suffix
  # on every entry, so `fr` alone would be rejected here.
  if [[ "$language" == "auto" ]]; then
    args+=(--data-urlencode "preferredVariants=en-US,de-DE,fr-FR")
  fi
  local body
  body=$(curl -sS -w $'\n---HTTP_STATUS:%{http_code}' -X POST "$URL" "${args[@]}" "$@")
  local status="${body##*---HTTP_STATUS:}"
  local json="${body%$'\n'---HTTP_STATUS:*}"
  echo "HTTP $status"
  if [[ "$status" != "200" ]] || ! echo "$json" | jq empty 2>/dev/null; then
    echo "Non-JSON or error response:"
    echo "$json" | head -c 500
    echo
    SUMMARY_KEYS+=("$label")
    SUMMARY_VALUES+=("")
    return
  fi
  if [[ "$language" == "auto" ]]; then
    local detected
    detected=$(echo "$json" | jq -r '.language.code // "(none)"')
    echo "Detected language: $detected"
  fi
  echo "$json" | jq -r '.matches[] | "\(.rule.id)\t\(.rule.category.id)\t\(.rule.issueType // "-")\t\(.context.text[.context.offset:(.context.offset + .context.length)])"'
  local unique_rules
  unique_rules=$(echo "$json" | jq -r '.matches[].rule.id' | sort -u | paste -sd, -)
  SUMMARY_KEYS+=("$label")
  SUMMARY_VALUES+=("$unique_rules")
  echo
}

run_tier() {
  local tier="$1"; shift
  local entry lang text
  for entry in "${SAMPLES[@]}"; do
    lang="${entry%%|*}"
    text="${entry#*|}"
    probe "$tier / $lang" "$lang" "$text" "$@"
    # Rate-limit courtesy; bump to 2 or 3 if anonymous tier starts
    # returning 429s on the longer runs.
    sleep 1
  done
}

run_tier "ANONYMOUS"

if [[ -n "$LANGUAGETOOL_USERNAME" && -n "$LANGUAGETOOL_API_KEY" ]]; then
  run_tier "PREMIUM" \
    --data-urlencode "username=$LANGUAGETOOL_USERNAME" \
    --data-urlencode "apiKey=$LANGUAGETOOL_API_KEY"
else
  echo "Skipping PREMIUM tier (LANGUAGETOOL_USERNAME / LANGUAGETOOL_API_KEY not set)"
fi

# Collect the unique set of rule IDs seen across all probes, with an
# example match text per rule so reviewers can judge whether it SHOULD
# be classified as spelling.
echo
echo "=== RULE ID CLASSIFICATION ==="
echo "(Y = classified as unknown-word rule → 'Add to dictionary' code action is offered.)"
printf "%-8s %-8s %s\n" "Current" "Proposed" "Rule ID"
printf "%-8s %-8s %s\n" "-------" "--------" "-------"

ALL_RULES=$(
  for v in "${SUMMARY_VALUES[@]}"; do
    [[ -z "$v" ]] && continue
    echo "$v" | tr ',' '\n'
  done | sort -u
)

new_cov_count=0
still_missed_count=0
for rid in $ALL_RULES; do
  cur="N"; prop="N"
  is_current_unknown_word_rule "$rid" && cur="Y"
  is_proposed_unknown_word_rule "$rid" && prop="Y"
  marker=""
  if [[ "$cur" == "N" && "$prop" == "Y" ]]; then
    marker="  ← new coverage"
    new_cov_count=$((new_cov_count + 1))
  elif [[ "$cur" == "N" && "$prop" == "N" ]]; then
    marker="  ← missed — inspect probe output to judge if it's a spell rule"
    still_missed_count=$((still_missed_count + 1))
  fi
  printf "%-8s %-8s %s%s\n" "$cur" "$prop" "$rid" "$marker"
done

echo
echo "=== SUMMARY ==="
echo "New rule IDs covered by proposed predicate: $new_cov_count"
echo "Rule IDs missed by both predicates: $still_missed_count (may include legitimate non-spelling rules)"
echo
placeholder_count=0
for entry in "${SAMPLES[@]}"; do
  [[ "${entry#*|}" == "PLACEHOLDER" ]] && placeholder_count=$((placeholder_count + 1))
done
echo "Languages still needing test samples: $placeholder_count"
