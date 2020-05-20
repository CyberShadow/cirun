#!/bin/bash
source ./lib.bash

# Test HTTP using Nginx as reverse proxy.

cat >> cirun.conf <<EOF
[server.main]
listen.addr = $test_ip
listen.port = $test_port2
EOF

"$cirun" server &
pid_cirun=$!
sleep 0.1

cat > nginx.conf <<EOF
pid        $test_dir/nginx.pid;

events {}

http {
  client_body_temp_path $test_dir;
  fastcgi_temp_path $test_dir;
  uwsgi_temp_path $test_dir;
  scgi_temp_path $test_dir;
  access_log   $test_dir/access.log;

  server {
    listen       $test_ip:$test_port;

    location / {
      proxy_pass   http://$test_ip:$test_port2;
    }
  }
}
EOF

nginx -c "$PWD"/nginx.conf

sleep 0.1

diff -u <(curl -vfsS "http://$test_ip:$test_port/ping") <(echo pong)

kill "$(cat "$test_dir"/nginx.pid)"
kill $pid_cirun
wait
