#!/bin/bash
source ./lib.bash

# Test runner is killed during execution,
# and the work directory (containing the lock files) disappeared.

git init -q "$test_dir"/repo
printf '#!/bin/sh\n\n\nsleep 1\n' > "$test_dir"/repo/.cirun
chmod +x "$test_dir"/repo/.cirun
git -C "$test_dir"/repo add -A
git -C "$test_dir"/repo commit -qm 'Initial commit'
commit=$(git -C "$test_dir"/repo rev-parse HEAD)

"$cirun" run --job-id-file=jobid --quiet repo "$test_dir"/repo "$commit"
jobid=$(cat jobid)
sleep 0.5
pkill -f "$jobid"

rm -rf cirun-work

"$cirun" status repo 2>&1 | grep -F 'Status: errored (job work directory disappeared)'
