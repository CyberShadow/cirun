#!/bin/bash
source ./lib.bash

# Test FastCGI using Apache 2 (in TCP mode).

cat >> cirun.conf <<EOF
[server.main]
protocol = fastcgi
listen.addr = $test_ip
listen.port = $test_port2
EOF

"$cirun" server &
pid_cirun=$!
sleep 0.1

cat > apache.conf <<EOF
ServerName 127.0.0.1
ServerAdmin cirun@localhost
PidFile "$PWD/apache.pid"
Listen ${test_ip}:${test_port}
ErrorLog /dev/stderr

LoadModule alias_module modules/mod_alias.so
LoadModule authz_core_module modules/mod_authz_core.so
LoadModule unixd_module modules/mod_unixd.so
LoadModule mpm_prefork_module modules/mod_mpm_prefork.so
LoadModule proxy_module modules/mod_proxy.so
LoadModule proxy_fcgi_module modules/mod_proxy_fcgi.so

ProxyPass "/"  "fcgi://$test_ip:$test_port2/"
EOF

httpd -f "$PWD"/apache.conf -X &
pid_httpd=$!

sleep 0.1

diff -u <(curl -fsS "http://$test_ip:$test_port/ping") <(echo pong)

kill "$pid_httpd"
kill "$pid_cirun"
wait
