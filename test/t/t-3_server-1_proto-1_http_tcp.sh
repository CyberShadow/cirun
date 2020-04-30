#!/bin/bash
source ./lib.bash

# Test HTTP over TCP.

printf '[server.main]\nlisten.addr = %s\nlisten.port = %d\n' "$test_ip" "$test_port" >> cirun.conf

"$cirun" server &
server=$!
sleep 0.1

diff -u <(curl -fsS "http://$test_ip:$test_port/ping") <(echo pong)

kill $server
wait
