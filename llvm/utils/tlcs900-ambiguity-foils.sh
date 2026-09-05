#!/usr/bin/env bash
# Foil the TLCS900 ambiguity guard: make it go RED on the two defects the
# encoding selectors exist to prevent, then show the untouched tree GREEN.
#
# QUESTION THIS ANSWERS
#   Can tlcs900-ambiguity-baseline.sh (and the lit test
#   TableGen/tlcs900-no-new-ambiguity.td, which runs the same report) SEE a
#   def that joins a selector family without its selector?  A guard that was
#   never made red certifies nothing.
#
# FOIL c  strip the WHOLE :i3 selector from CP8_small -- both the
#         FormI3.AsmTail spelling AND the immi3_8 operand class (-> i8imm).
#         Only then does CP8_small share CP8ri's exact matchable
#         (`cp <GR8>, <imm>`, imm parsed as i8imm) and the report grow by one
#         pair naming CP8_small and CP8ri.  Removing the AsmString tail ALONE
#         leaves the report at 1: immi3_8's ParserMatchClass still
#         disambiguates it, correctly.  The selector is TWO parts, not one
#         (measured 2026-09-05 -- a tail-only edit was the original, wrong foil).
# FOIL d  append a throwaway `def CP8_tiny` with CP8ri's shape and no
#         selector.  The report must grow by one pair naming CP8_tiny and
#         CP8ri.  A spelling-keyed checker passes this case -- the family is
#         already declared -- which is why LLVM's own analysis is the guard.
#
# Each foil is applied to a SCRATCH COPY of llvm/lib/Target/TLCS900; the tree
# is never modified.  Afterwards the baseline script runs on the real tree and
# must be green.  REQUIRES an assertions build of llvm-tblgen.
#
# RUN, from anywhere:
#   llvm/utils/tlcs900-ambiguity-foils.sh [path/to/llvm-tblgen]
#   exit 0 = both foils RED and the real tree GREEN; anything else = a guard
#   that cannot fail, or a tree that is not at the baseline.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
LLVM=$HERE/..
TBLGEN=${1:-$LLVM/../build/bin/llvm-tblgen}
BASELINE_PAIRS=1
TD=TLCS900InstrInfo.td
FAIL=0

report() {  # $1 = dir holding the .td copy
  "$TBLGEN" -gen-asm-matcher -debug-only=ambiguous_instrs \
    -I "$1" -I "$LLVM/include" "$1/TLCS900.td" -o /dev/null 2>&1
}
pairs() { printf '%s\n' "$1" | grep -c '^warning: ambiguous matchables:'; }
names() { printf '%s\n' "$1" | grep -oP '^\S+(?= -- flattened:)' | sort -u | tr '\n' ' '; }

run_foil() {  # $1 = letter, $2 = description, $3 = matchable that must be named
  local T; T=$(mktemp -d)
  cp -r "$LLVM/lib/Target/TLCS900" "$T/"
  python3 - "$1" "$T/TLCS900/$TD" <<'PY'
import sys
foil, p = sys.argv[1], sys.argv[2]
s = open(p).read()
if foil == 'c':
    # BOTH halves of the :i3 selector, or the pair stays non-ambiguous: the
    # immi3_8 ParserMatchClass alone keeps the matcher able to tell them apart.
    i = s.index('def CP8_small'); seg = s[i:i + 400]
    assert 'immi3_8:$imm' in seg and 'FormI3.AsmTail' in seg, 'CP8_small def not where expected'
    seg = seg.replace('(ins GR8:$rs1, immi3_8:$imm)', '(ins GR8:$rs1, i8imm:$imm)')
    seg = seg.replace('"cp", !strconcat("$rs1, ${imm}", FormI3.AsmTail), []>,',
                      '"cp", "$rs1, $imm", []>,')
    s = s[:i] + seg + s[i + 400:]
elif foil == 'd':
    s += ('\ndef CP8_tiny : PrefixSmallImmInst<0xD8, (outs), '
          '(ins GR8:$rs1, i8imm:$imm), "cp", "$rs1, $imm", []>;\n')
open(p, 'w').write(s)
PY
  local R P N
  R=$(report "$T/TLCS900"); P=$(pairs "$R"); N=$(names "$R")
  echo "FOIL $1 -- $2"
  echo "  ambiguous pairs: $P (baseline $BASELINE_PAIRS); matchables: $N"
  if [ "$P" -gt "$BASELINE_PAIRS" ] && printf '%s' "$N" | grep -q "$3"; then
    echo "  RED as required"
  else
    echo "  FAIL: the guard did not go red"; FAIL=1
    printf '%s\n' "$R" | grep -m3 'error' | sed 's/^/  tblgen: /'
  fi
  rm -rf "$T"
}

run_foil c "CP8_small loses its whole :i3 selector (asm tail + immi3_8 class)" CP8_small
run_foil d "a throwaway CP8_tiny joins the cp.r8.imm family with no selector" CP8_tiny

echo "CONTROL -- the untouched tree"
if "$HERE/tlcs900-ambiguity-baseline.sh" "$TBLGEN"; then
  echo "  GREEN as required"
else
  echo "  FAIL: the real tree is not at the baseline"; FAIL=1
fi
[ "$FAIL" -eq 0 ] && echo "OK: both foils red, control green"
exit $FAIL
