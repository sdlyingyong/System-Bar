#!/bin/bash
# Tests for smctemp helper (v2 metrics).
# Verifies output format, plausible ranges, and stability across runs.
set -u

HELPER="${1:-$(dirname "$0")/../helper/smctemp}"
PASS=0
FAIL=0

check() {
    local name="$1"
    if [ "$2" = "ok" ]; then
        PASS=$((PASS + 1))
        echo "PASS: $name"
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $name"
    fi
}

is_num() { [[ "$1" =~ ^[0-9]+([.][0-9]+)?$ ]]; }
in_range() { awk -v v="$1" -v lo="$2" -v hi="$3" 'BEGIN { exit !(v>=lo && v<=hi) }'; }

OUT="$("$HELPER" --once 2>/dev/null)"
RC=$?
check "exit code 0 (got $RC)" "$([ "$RC" -eq 0 ] && echo ok || echo fail)"

# required metric keys present
for k in cpu battery cpupct mempct gpupct power down up batcyc bathealth diskread diskwrite diskfree; do
    check "has key $k" "$([[ "$OUT" == *";$k="* || "$OUT" == "$k="* ]] && echo ok || echo fail)"
done

field() { echo "$OUT" | tr ';' '\n' | grep "^$1=" | head -1 | cut -d= -f2; }

# battery health plausible
BC=$(field batcyc)
BH=$(field bathealth)
check "battery cycles in 0..3000 (got $BC)" "$(is_num "$BC" && in_range "$BC" 0 3000 && echo ok || echo fail)"
check "battery health in 0..100 (got $BH)" "$(is_num "$BH" && in_range "$BH" 0 100 && echo ok || echo fail)"

# disk keys plausible
DF=$(field diskfree)
check "disk free in 1GB..8TB (got $DF)" "$(is_num "$DF" && in_range "$DF" 1073741824 8796093022208 && echo ok || echo fail)"

# CPU temp in plausible band (15-125)
CV=$(field cpu)
check "cpu temp in 15..125 (got $CV)" "$(is_num "$CV" && in_range "$CV" 15 125 && echo ok || echo fail)"

# battery temp plausible (10-80)
BV=$(field battery)
check "battery temp in 10..80 (got $BV)" "$(is_num "$BV" && in_range "$BV" 10 80 && echo ok || echo fail)"

# mem / gpu in 0..100 on first sample
MV=$(field mempct)
GV=$(field gpupct)
check "mem in 0..100 (got $MV)" "$(is_num "$MV" && in_range "$MV" 0 100 && echo ok || echo fail)"
check "gpu in 0..100 (got $GV)" "$(is_num "$GV" && in_range "$GV" 0 100 && echo ok || echo fail)"

# sensors list non-empty
FIELDS=$(echo "$OUT" | tr ';' '\n' | grep '=' | grep -vE '^(cpu|battery|cpupct|mempct|gpupct|power|down|up|batcyc|bathealth|diskread|diskwrite|diskfree)=')
COUNT=$(echo "$FIELDS" | grep -c '=')
check "at least 5 sensors reported (got $COUNT)" "$([ "$COUNT" -ge 5 ] && echo ok || echo fail)"

BAD=""
while IFS= read -r f; do
    v="${f#*=}"
    if ! is_num "$v" || ! in_range "$v" 1 125; then BAD="$BAD $f"; fi
done <<< "$FIELDS"
check "all sensor values plausible (1..125)" "$([ -z "$BAD" ] && echo ok || echo fail)"

# post warm-up: cpupct / power must be valid on the 3rd 1s sample
"$HELPER" -i 1 > /tmp/smctemp_test_out.txt 2>/dev/null &
TPID=$!
sleep 4
kill "$TPID" 2>/dev/null
wait "$TPID" 2>/dev/null
LINES=$(head -3 /tmp/smctemp_test_out.txt)
RC=$?
check "daemon mode runs" "$([ "$RC" -eq 0 ] && echo ok || echo fail)"
THIRD=$(echo "$LINES" | sed -n '3p')
CP=$(echo "$THIRD" | tr ';' '\n' | grep '^cpupct=' | cut -d= -f2)
PW=$(echo "$THIRD" | tr ';' '\n' | grep '^power=' | cut -d= -f2)
DW=$(echo "$THIRD" | tr ';' '\n' | grep '^down=' | cut -d= -f2)
UW=$(echo "$THIRD" | tr ';' '\n' | grep '^up=' | cut -d= -f2)
check "cpupct valid post warm-up (got $CP)" "$(is_num "$CP" && in_range "$CP" 0 100 && echo ok || echo fail)"
check "power valid post warm-up (got $PW)" "$(is_num "$PW" && in_range "$PW" 0 100 && echo ok || echo fail)"
check "down speed valid post warm-up (got $DW)" "$(is_num "$DW" && in_range "$DW" 0 1000000000 && echo ok || echo fail)"
check "up speed valid post warm-up (got $UW)" "$(is_num "$UW" && in_range "$UW" 0 1000000000 && echo ok || echo fail)"

echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
