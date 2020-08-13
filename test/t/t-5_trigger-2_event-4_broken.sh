#!/bin/bash
source ./lib.bash

# Test the "broken" trigger event.

git init -q "$test_dir"/repo
printf '#!/bin/sh\n\n\ntrue\n' > "$test_dir"/repo/.cirun
chmod +x "$test_dir"/repo/.cirun
git -C "$test_dir"/repo add -A
git -C "$test_dir"/repo commit -qm 'Initial commit'
commit1=$(git -C "$test_dir"/repo rev-parse HEAD)
printf '#!/bin/sh\n\n\nfalse\n' > "$test_dir"/repo/.cirun
git -C "$test_dir"/repo commit -qam 'Break it'
commit2=$(git -C "$test_dir"/repo rev-parse HEAD)

cat >> cirun.conf <<EOF
[trigger.test]
type = exec
events = [queued, starting, running, succeeded, failed, errored, cancelled, broken, fixed]
exec.command = ["$PWD/trigger.sh"]
EOF

cat >> trigger.sh <<EOF
#!/bin/sh
echo "\$CIRUN_EVENT" >> "$PWD"/events.txt
EOF
chmod +x ./trigger.sh

"$cirun" run --wait repo "$commit1" --ref refs/heads/master --clone-url "$test_dir"/repo
"$cirun" run --wait repo "$commit2" --ref refs/heads/master --clone-url "$test_dir"/repo

diff -u events.txt /dev/stdin <<EOF
queued
starting
running
succeeded
queued
starting
running
failed
broken
EOF
