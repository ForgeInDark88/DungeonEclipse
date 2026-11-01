#!/bin/bash
# World session test: a host and seven clients on one machine (headless).
# Usage: bash tests/world_net.sh [log dir]
cd "$(dirname "$0")/.."
L=${1:-/tmp/world_net}
mkdir -p $L
P=7791
run() { timeout 60 godot --headless --path . -s tests/world_net_sim.gd > $L/$1.log 2>&1; }
ROLE=host PORT=$P PASS=pw SEATS=3 STAY=34 DENY_PENDING=1 run host &
HP=$!
sleep 3
# Alice: a new profile; she marks her gold and leaves
ROLE=client PORT=$P PASS=pw NICK=Alice EXPECT=ok GOLD_MARK=123 STAY=4 TOKEN_FILE=$L/alice.cfg run alice1 &
sleep 2
# the same nick (another case) while Alice is online: refused
ROLE=client PORT=$P PASS=pw NICK=alice EXPECT=nick TOKEN_FILE=$L/alice.cfg run alice_dup &
# a wrong password; another build of the game
ROLE=client PORT=$P PASS=nope NICK=Mallory EXPECT=password TOKEN_FILE=$L/mal.cfg run badpass &
ROLE=client PORT=$P PASS=pw NICK=Vera EXPECT=version PROTOCOL_LIE=1 TOKEN_FILE=$L/vera.cfg run version &
wait $!
sleep 4
# Alice back with her token: her gold comes back with her
ROLE=client PORT=$P PASS=pw NICK=Alice EXPECT=ok CHECK_GOLD=123 STAY=10 TOKEN_FILE=$L/alice.cfg run alice2 &
sleep 2
# someone else's device with Alice's nick: the host refuses the bind
ROLE=client PORT=$P PASS=pw NICK=Alice EXPECT=nick TOKEN_FILE=$L/thief.cfg run thief_online &
sleep 1
ROLE=client PORT=$P PASS=pw NICK=Bob EXPECT=ok STAY=12 TOKEN_FILE=$L/bob.cfg run bob &
sleep 3
# host + Alice + Bob = 3 seats: full
ROLE=client PORT=$P PASS=pw NICK=Carl EXPECT=full TOKEN_FILE=$L/carl.cfg run carl &
sleep 9
# Alice gone: a stranger with her nick and another token is refused
ROLE=client PORT=$P PASS=pw NICK=Alice EXPECT=token TOKEN_FILE=$L/thief.cfg run thief &
sleep 3
ROLE=client PORT=$P PASS=pw NICK=Kickme EXPECT=ok STAY=8 TOKEN_FILE=$L/kick.cfg run kickme &
wait $HP
wait
grep -h "FAIL\|RESULT\|ROSTER\|PROFILES" $L/*.log
