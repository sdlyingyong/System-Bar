#!/bin/bash
# Tests for smctemp helper.
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

# 1. --once runs, exits 0, prints cpu= first
OUT="$("$HELPER" --once 2>/dev/null)"
RC=$?
check "exit code 0 (got $RC)" "$([ "$RC" -eq 0 ] && echo ok || echo fail)"

CPU="${OUT%%;*}"
check "line starts with cpu=" "$([[ "$CPU" == cpu=* ]] && echo ok || echo fail)"

CVAL="${CPU#cpu=}"
check "cpu value is numeric (got '$CVAL')" "$(is_num "$CVAL" && echo ok || echo fail)"

# 2. cpu in plausible band (15-125 °C)
IN_BAND=$(awk -v v="$CVAL" 'BEGIN { print (v>=15 && v<=125) ? 1 : 0 }')
check "cpu in 15..125 °C (got $CVAL)" "$([ "$IN_BAND" = 1 ] && echo ok || echo fail)"

# 3. all sensor values plausible (1-125), non-empty list
FIELDS=$(echo "$OUT" | tr ';' '\n' | grep '=' | grep -v '^cpu=')
COUNT=$(echo "$FIELDS" | grep -c '=')
check "at least 5 sensors reported (got $COUNT)" "$([ "$COUNT" -ge 5 ] && echo ok || echo fail)"

BAD=""
while IFS= read -r f; do
    v="${f#*=}"
    if ! is_num "$v" || ! awk -v v="$v" 'BEGIN { exit !(v>=1 && v<=125) }'; then
        BAD="$BAD $f"
    fi
done <<< "$FIELDS"
check "all sensor values plausible (1..125)" "$([ -z "$BAD" ] && echo ok || echo fail)"

# 4. stability: 5 runs all succeed with non-empty cpu
for i in 1 2 3 4 5; do
    O="$("$HELPER" --once 2>/dev/null)"
    R=$?
    if [ $R -ne 0 ] || [[ "$O" != cpu=* ]] || [ -z "$O" ]; then
        check "stability run $i (rc=$R out=$O)" "fail"
        break
    fi
    if [ $i -eq 5 ]; then check "stability (5 runs)" "ok"; fi
done

echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
