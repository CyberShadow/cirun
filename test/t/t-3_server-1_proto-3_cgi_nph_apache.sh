#!/bin/bash
source ./lib.bash

# Test CGI (in NPH mode) using Apache 2.

cat >> cirun.conf <<EOF
[server.cgi]
prefix = /nph-cirun/
EOF

ln -s cirun nph-cirun

cat > apache.conf <<EOF
ServerName 127.0.0.1
ServerAdmin cirun@localhost
PidFile "$PWD/apache.pid"
Listen ${test_ip}:${test_port}
ErrorLog /dev/stderr

LoadModule alias_module modules/mod_alias.so
LoadModule authz_core_module modules/mod_authz_core.so
LoadModule cgi_module modules/mod_cgi.so
LoadModule unixd_module modules/mod_unixd.so
LoadModule mpm_prefork_module modules/mod_mpm_prefork.so

ScriptAlias "/" "$(realpath "$(dirname "$cirun")")/"
EOF

httpd -f "$PWD"/apache.conf -X &
server=$!

sleep 0.1

diff -u <(curl -fsS "http://$test_ip:$test_port/nph-cirun/ping") <(echo pong)

kill $server
wait
