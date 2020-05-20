#!/bin/bash
source ./lib.bash

# Test HTTP over TCP.

cat >> cirun.conf <<EOF
[server.main]
listen.addr = $test_ip
listen.port = $test_port
EOF

"$cirun" server &
pid_cirun=$!
sleep 0.1

diff -u <(curl -fsS "http://$test_ip:$test_port/ping") <(echo pong)

kill "$pid_cirun"
wait
