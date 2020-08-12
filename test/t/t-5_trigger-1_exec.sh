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
type = exec
events = [succeeded]
exec.command = ["$PWD/trigger.sh"]
EOF

cat >> trigger.sh <<EOF
#!/bin/bash
env | grep ^CIRUN_ | grep -v ^CIRUN_BUILT= | sort > "$PWD"/env.txt
EOF
chmod +x ./trigger.sh

"$cirun" run --job-id-file=jobid --wait repo "$commit" --clone-url "$test_dir"/repo
jobid=$(cat jobid)

diff -u env.txt /dev/stdin <<EOF
CIRUN_COMMIT=$commit
CIRUN_EVENT=succeeded
CIRUN_JOB=$jobid
CIRUN_REPO=repo
EOF
