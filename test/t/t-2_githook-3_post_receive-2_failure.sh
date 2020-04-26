#!/bin/bash
source ./lib.bash

# Test the post-receive hook with a failing build.

git init -q "$test_dir"/repo
printf '#!/bin/sh\n\n\nfalse\n' > "$test_dir"/repo/.cirun
chmod +x "$test_dir"/repo/.cirun
git -C "$test_dir"/repo add -A
git -C "$test_dir"/repo commit -qm 'Initial commit'

git init -q --bare "$test_dir"/repo.bare
"$cirun" install-git-hook post-receive "$test_dir"/repo.bare repo

git -C "$test_dir"/repo remote add origin "$test_dir"/repo.bare
git -C "$test_dir"/repo push origin master

sleep 0.1

"$cirun" status repo 2>&1 | grep -F 'Status: failure'
