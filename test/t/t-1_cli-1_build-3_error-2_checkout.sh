#!/bin/bash
source ./lib.bash

# Git checkout error.

git init -q "$test_dir"/repo
printf '#!/bin/sh\n\n\ntrue\n' > "$test_dir"/repo/.cirun
chmod +x "$test_dir"/repo/.cirun
git -C "$test_dir"/repo add -A
git -C "$test_dir"/repo commit -qm 'Initial commit'

"$cirun" run --wait repo "$test_dir"/repo 0123456789012345678901234567890123456789 2>&1 | grep -F 'Status: errored (Check-out failed with status'
