#!/bin/bash
source ./lib.bash

# Script execution error.

git init -q "$test_dir"/repo
touch "$test_dir"/repo/.cirun
chmod +x "$test_dir"/repo/.cirun
git -C "$test_dir"/repo add -A
git -C "$test_dir"/repo commit -qm 'Initial commit'
commit=$(git -C "$test_dir"/repo rev-parse HEAD)

"$cirun" run --wait repo "$commit" --clone-url "$test_dir"/repo 2>&1 | grep -F 'Status: errored (Failed to execute program (Exec format error))'
