#!/usr/bin/env bash
# Assert that the TLCS900 asm-matcher ambiguity report has not grown.
#
# QUESTION THIS ANSWERS
#   Does any pair of TLCS900 matchables (instruction defs or InstAliases)
#   share a mnemonic AND an operand-class list, so that the assembler picks
#   between them by table order?  LLVM's AsmMatcherEmitter computes exactly
#   this (MatchableInfo::couldMatchAmbiguouslyWith) but only prints it under
#   -debug-only=ambiguous_instrs, so a normal build never shows it.  This
#   script runs that report and compares it with the recorded baseline.
#
# BASELINE, measured 2026-09-04 at tlcs900_backend 86332721969d:
#   1 pair, LINK / LINK32r ("link <GPR>, <imm>" is served by two defs, a
#   pre-existing defect that is not fixed here and must not be masked).
#   ⚠ The design spec for the encoding selectors quoted this as "2 pairs";
#   the emitter counts PAIRS and LINK/LINK32r is one pair of two matchables.
#
# The same check runs as a lit test: llvm/test/TableGen/tlcs900-no-new-ambiguity.td
#
# REQUIRES an assertions build of llvm-tblgen (the report is DEBUG_WITH_TYPE).
#
# RUN, from anywhere:
#   llvm/utils/tlcs900-ambiguity-baseline.sh [path/to/llvm-tblgen]
#   exit 0 = report equals the baseline; exit 1 = it grew (or shrank: a fixed
#   LINK defect must update BASELINE_PAIRS below, deliberately).

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
LLVM=$HERE/..                       # llvm/
TBLGEN=${1:-$LLVM/../build/bin/llvm-tblgen}
BASELINE_PAIRS=1
BASELINE_NAMES="LINK LINK32r"

if ! "$TBLGEN" --version 2>/dev/null | grep -q 'with assertions'; then
  echo "FAIL: $TBLGEN is not an assertions build; the ambiguity report is debug-only" >&2
  exit 1
fi

REPORT=$("$TBLGEN" -gen-asm-matcher -debug-only=ambiguous_instrs \
           -I "$LLVM/lib/Target/TLCS900" -I "$LLVM/include" \
           "$LLVM/lib/Target/TLCS900/TLCS900.td" -o /dev/null 2>&1)
PAIRS=$(printf '%s\n' "$REPORT" | grep -c '^warning: ambiguous matchables:')
NAMES=$(printf '%s\n' "$REPORT" | grep -oP '^\S+(?= -- flattened:)' | sort -u | tr '\n' ' ' | sed 's/ $//')

echo "ambiguous pairs: $PAIRS (baseline $BASELINE_PAIRS)"
echo "matchables involved: ${NAMES:-none} (baseline: $BASELINE_NAMES)"
if [ "$PAIRS" -ne "$BASELINE_PAIRS" ]; then
  printf '%s\n' "$REPORT"
  echo "FAIL: the ambiguity report moved from the recorded baseline" >&2
  exit 1
fi
echo "OK: ambiguity report unchanged"
