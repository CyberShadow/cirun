#!/bin/bash
source ./lib.bash

git init -q "$test_dir"/repo
printf '#!/bin/sh\n\n\ntrue\n' > "$test_dir"/repo/.cirun
chmod +x "$test_dir"/repo/.cirun
git -C "$test_dir"/repo add -A
git -C "$test_dir"/repo commit -qm 'Initial commit'
commit=$(git -C "$test_dir"/repo rev-parse HEAD)

cat >> cirun.conf <<EOF
[trigger.test]
type = giteaCommitStatus
events = [succeeded]
gitea.endpoint = http://$test_ip:$test_port/
gitea.token = 0123456789abcdef0123456789abcdef01234567
EOF

printf 'HTTP/1.0 200 OK\r\n\r\n' | ncat -v -l $test_ip $test_port > response.http &

"$cirun" run --job-id-file=jobid --wait repo "$test_dir"/repo "$commit"
jobid=$(cat jobid)

wait
diff -u response.http <(
	printf 'POST /repos/repo/statuses/%s HTTP/1.0\r\n' "$commit"
	printf 'User-Agent: ae.net.http.client (+https://github.com/CyberShadow/ae)\r\n'
	printf 'Host: %s:%s\r\n' $test_ip $test_port
	printf 'Content-Type: application/json\r\n'
	printf 'Connection: close\r\n'
	printf 'Authorization: token 0123456789abcdef0123456789abcdef01234567\r\n'
	printf 'Content-Length: 107\r\n'
	printf 'Accept-Encoding: gzip, deflate, *;q=0\r\n'
	printf '\r\n'
	printf '{"context":"cirun","description":"Job succeeded","state":"success","target_url":"job/%s"}' "$jobid"
)
