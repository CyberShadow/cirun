#!/bin/bash
source ./lib.bash

# Test SCGI using nginx.

cat >> cirun.conf <<EOF
[server.main]
protocol = scgi
listen.addr = $test_ip
listen.port = $test_port2
EOF

"$cirun" server &
pid_cirun=$!
sleep 0.1

cat > nginx.conf <<EOF
daemon off;
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
      include /etc/nginx/scgi_params;
      scgi_pass   $test_ip:$test_port2;
    }
  }
}
EOF

nginx -c "$PWD"/nginx.conf &
pid_httpd=$!
sleep 0.1

sleep 0.1

diff -u <(curl -fsS "http://$test_ip:$test_port/ping") <(echo pong)

kill "$pid_httpd"
kill "$pid_cirun"
wait
