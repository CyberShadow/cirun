#!/bin/bash
source ./lib.bash

# Job data directory gone.

git init -q "$test_dir"/repo
printf '#!/bin/sh\n\n\ntrue\n' > "$test_dir"/repo/.cirun
chmod +x "$test_dir"/repo/.cirun
git -C "$test_dir"/repo add -A
git -C "$test_dir"/repo commit -qm 'Initial commit'
commit=$(git -C "$test_dir"/repo rev-parse HEAD)

"$cirun" run --job-id-file=jobid --quiet --wait repo "$test_dir"/repo "$commit"
jobid=$(cat jobid)

rm -rf cirun-data/jobs

"$cirun" status repo 2>&1 | grep -F 'Status: (no data)'
"$cirun" log 2>&1 | grep -F "(no data) $jobid"
