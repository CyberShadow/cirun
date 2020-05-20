#!/bin/bash
source ./lib.bash

# Test FastCGI using Apache 2.

cat >> cirun.conf <<EOF
[server.fastcgi]
transport = accept
protocol = fastcgi
prefix = /cirun/
EOF

cat > apache.conf <<EOF
ServerName 127.0.0.1
ServerAdmin cirun@localhost
PidFile "$PWD/apache.pid"
Listen ${test_ip}:${test_port}
ErrorLog /dev/stderr

LoadModule alias_module modules/mod_alias.so
LoadModule authz_core_module modules/mod_authz_core.so
LoadModule unixd_module modules/mod_unixd.so
LoadModule fcgid_module modules/mod_fcgid.so
LoadModule mpm_prefork_module modules/mod_mpm_prefork.so

Suexec Off
FcgidIPCDir "$PWD"
FcgidProcessTableFile "$PWD/fcgid_shm"

<Directory "$(realpath "$(dirname "$cirun")")/">
	SetHandler fcgid-script
	Options +ExecCGI
</Directory>

ScriptAlias "/" "$(realpath "$(dirname "$cirun")")/"
EOF

httpd -f "$PWD"/apache.conf -X &
server=$!

sleep 0.1

diff -u <(curl -vfsS "http://$test_ip:$test_port/cirun/ping") <(echo pong)

kill $server
wait
