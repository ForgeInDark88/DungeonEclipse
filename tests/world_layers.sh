#!/bin/bash
# A split party in a location of layers: a host and two guests build the
# same location (hashes match); Ann goes down to the first floor, Ben stays
# on the surface with the host; the host simulates both layers, the empty
# ones sleep; each guest hears only about its own layer; then the host calls
# everybody down.

cd "$(dirname "$0")/.."
L=${1:-/tmp/world_layers}
mkdir -p $L
P=7798
run() { timeout 90 godot --headless --path . -s tests/world_net_sim.gd > $L/$1.log 2>&1; }
SCENARIO=layers ROLE=host PORT=$P SEATS=4 SAVES=user://test_layers_saves/ run host &
HP=$!
sleep 3
SCENARIO=layers ROLE=client PORT=$P NICK=Ann EXPECT=ok TOKEN_FILE=$L/ann.cfg run ann &
sleep 1
SCENARIO=layers ROLE=client PORT=$P NICK=Ben EXPECT=ok TOKEN_FILE=$L/ben.cfg run ben &
wait $HP
wait
grep -h "FAIL\|RESULT" $L/*.log
FAILED=0
H=$(grep -h "^HASH 0:" $L/host.log)
for c in ann ben; do
  C=$(grep -h "^HASH 0:" $L/$c.log)
  if [ "$H" == "$C" ] && [ -n "$H" ]; then echo "$c: same location ($H)"; else echo "$c: DESYNC host='$H' $c='$C'"; FAILED=1; fi
done
grep -h "^BANDS" $L/host.log
grep -q "FAIL" $L/*.log && FAILED=1
exit $FAILED

