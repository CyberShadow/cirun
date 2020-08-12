#!/bin/bash
source ./lib.bash

# Job data file corrupted.

git init -q "$test_dir"/repo
printf '#!/bin/sh\n\n\ntrue\n' > "$test_dir"/repo/.cirun
chmod +x "$test_dir"/repo/.cirun
git -C "$test_dir"/repo add -A
git -C "$test_dir"/repo commit -qm 'Initial commit'
commit=$(git -C "$test_dir"/repo rev-parse HEAD)

"$cirun" run --job-id-file=jobid --quiet --wait repo "$commit" --clone-url "$test_dir"/repo
jobid=$(cat jobid)

echo garbage > cirun-data/jobs/*/*/job.json

"$cirun" status repo 2>&1 | grep -F 'Status: corrupted (Expected {, got g)'
"$cirun" history 2>&1 | grep -F "corrupted $jobid"
