#!/bin/bash
source ./lib.bash

# Test all event types in the job's life cycle up to "errored" (in execution).

git init -q "$test_dir"/repo
printf 'Not a program' > "$test_dir"/repo/.cirun
git -C "$test_dir"/repo add -A
git -C "$test_dir"/repo commit -qm 'Initial commit'
commit=$(git -C "$test_dir"/repo rev-parse HEAD)

cat >> cirun.conf <<EOF
[trigger.test]
type = exec
events = [queued, starting, running, succeeded, failed, errored, cancelled]
exec.command = ["$PWD/trigger.sh"]
EOF

cat >> trigger.sh <<EOF
#!/bin/sh
echo "\$CIRUN_EVENT" >> "$PWD"/events.txt
EOF
chmod +x ./trigger.sh

"$cirun" run --wait repo "$commit" --clone-url "$test_dir"/repo

diff -u events.txt /dev/stdin <<EOF
queued
starting
running
errored
EOF
