#!/bin/bash
source ./lib.bash

# Job data file corrupted.

git init -q "$test_dir"/repo
printf '#!/bin/sh\n\n\ntrue\n' > "$test_dir"/repo/.cirun
chmod +x "$test_dir"/repo/.cirun
git -C "$test_dir"/repo add -A
git -C "$test_dir"/repo commit -qm 'Initial commit'
commit=$(git -C "$test_dir"/repo rev-parse HEAD)

"$cirun" run --quiet --wait repo "$test_dir"/repo "$commit"

echo garbage >> cirun-data/jobs/*/*/log.json

diff -u <("$cirun" log repo 2>&1 | tail -n 3 | tr 0-9 '#') /dev/stdin <<'EOF'
[##:##:## +##:##.###] Process finished with exit code #
[##:##:## +##:##.###] Job finished with status success
                      (corrupted log entry)
EOF
