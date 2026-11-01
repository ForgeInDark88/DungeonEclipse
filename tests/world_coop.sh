#!/bin/bash
# Co-op run without desync: a host and two guests walk three locations;
# every machine prints the hash of the location's state (tiles, chests,
# enemies with their net ids) and the hashes must match.
cd "$(dirname "$0")/.."
L=${1:-/tmp/world_coop}
mkdir -p $L
P=7797
run() { timeout 90 godot --headless --path . -s tests/world_net_sim.gd > $L/$1.log 2>&1; }
SCENARIO=coop ROLE=host PORT=$P SEATS=4 SAVES=user://test_coop_saves/ run host &
HP=$!
sleep 3
SCENARIO=coop ROLE=client PORT=$P NICK=Ann EXPECT=ok TOKEN_FILE=$L/ann.cfg run ann &
sleep 1
SCENARIO=coop ROLE=client PORT=$P NICK=Ben EXPECT=ok TOKEN_FILE=$L/ben.cfg run ben &
wait $HP
wait
grep -h "FAIL\|RESULT" $L/*.log
FAILED=0
for k in 0 1 2; do
  H=$(grep -h "^HASH $k:" $L/host.log)
  for c in ann ben; do
    C=$(grep -h "^HASH $k:" $L/$c.log)
    if [ "$H" == "$C" ] && [ -n "$H" ]; then echo "location $k $c: same state ($H)"; else echo "location $k $c: DESYNC host='$H' $c='$C'"; FAILED=1; fi
  done
done
exit $FAILED
