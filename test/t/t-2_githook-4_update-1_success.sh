#!/bin/bash
source ./lib.bash

# Test the update hook with a successful build.

git init -q "$test_dir"/repo
printf '#!/bin/sh\n\n\ntrue\n' > "$test_dir"/repo/.cirun
chmod +x "$test_dir"/repo/.cirun
git -C "$test_dir"/repo add -A
git -C "$test_dir"/repo commit -qm 'Initial commit'

git init -q --bare "$test_dir"/repo.bare
"$cirun" install-git-hook update "$test_dir"/repo.bare repo

git -C "$test_dir"/repo remote add origin "$test_dir"/repo.bare
git -C "$test_dir"/repo push origin master
