#!/bin/bash
# The party follows the host through the loop (town → map → location →
# map → result → town): a host and a guest, headless.
cd "$(dirname "$0")/.."
L=${1:-/tmp/world_flow}
mkdir -p $L
P=7795
run() { timeout 60 godot --headless --path . -s tests/world_net_sim.gd > $L/$1.log 2>&1; }
SCENARIO=flow ROLE=host PORT=$P SEATS=4 SAVES=user://test_flow_saves/ run host &
HP=$!
sleep 3
SCENARIO=flow ROLE=client PORT=$P NICK=Guest EXPECT=ok TOKEN_FILE=$L/guest.cfg run guest &
wait $HP
wait
grep -h "FAIL\|RESULT\|STATES" $L/*.log
