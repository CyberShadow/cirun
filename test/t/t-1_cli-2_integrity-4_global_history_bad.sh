#!/bin/bash
source ./lib.bash

# Job data file corrupted.

git init -q "$test_dir"/repo
printf '#!/bin/sh\n\n\ntrue\n' > "$test_dir"/repo/.cirun
chmod +x "$test_dir"/repo/.cirun
git -C "$test_dir"/repo add -A
git -C "$test_dir"/repo commit -qm 'Initial commit'
commit=$(git -C "$test_dir"/repo rev-parse HEAD)

"$cirun" run --job-id-file=jobid --quiet --wait repo "$test_dir"/repo "$commit"
jobid=$(cat jobid)

echo garbage >> cirun-data/history.json

"$cirun" history 2>&1 | grep -F 'corrupted (corrupted global history entry)'
