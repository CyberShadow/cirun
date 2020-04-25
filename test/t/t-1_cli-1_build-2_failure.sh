#!/bin/bash
source ./lib.bash

# Failing test script.

git init -q "$test_dir"/repo
printf '#!/bin/sh\n\n\nfalse\n' > "$test_dir"/repo/.cirun
chmod +x "$test_dir"/repo/.cirun
git -C "$test_dir"/repo add -A
git -C "$test_dir"/repo commit -qm 'Initial commit'
commit=$(git -C "$test_dir"/repo rev-parse HEAD)

"$cirun" run --wait repo "$test_dir"/repo "$commit" 2>&1 | grep -F 'Status: failure (CI script failed with status 1)'
