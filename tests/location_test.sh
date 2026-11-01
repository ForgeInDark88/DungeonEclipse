#!/bin/bash
# tests/location_test.gd for every node type with layers, 4 at a time
# (200 seeds each by default; SEEDS=n for fewer).
cd "$(dirname "$0")/.."
L=${1:-/tmp/location_test}
mkdir -p $L
TYPES=$(ls data/locations/*.tres | xargs -n1 basename | sed 's/\.tres$//')
for t in $TYPES; do
  while [ $(jobs -r | wc -l) -ge 4 ]; do sleep 1; done
  TYPE=$t timeout 1500 godot --headless -s tests/location_test.gd > $L/$t.log 2>&1 &
done
wait
FAILED=0
for t in $TYPES; do
  echo "$t: $(grep -h '^locations:' $L/$t.log) $(grep -h '^FAILURES' $L/$t.log)"
  grep -h "^FAIL:" $L/$t.log | head -5
  grep -q "^FAILURES: 0" $L/$t.log || FAILED=1
done
exit $FAILED
