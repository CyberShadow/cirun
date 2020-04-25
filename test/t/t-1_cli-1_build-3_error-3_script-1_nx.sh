#!/bin/bash
source ./lib.bash

# No cirun script.

git init -q "$test_dir"/repo
git -C "$test_dir"/repo commit --allow-empty -qm 'Initial commit'
commit=$(git -C "$test_dir"/repo rev-parse HEAD)

"$cirun" run --wait repo "$test_dir"/repo "$commit" 2>&1 | grep -F 'Status: errored (No cirun script found or configured)'
