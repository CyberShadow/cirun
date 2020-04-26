#!/bin/bash
source ./lib.bash

# Test handling/display of scripts that
# print a whole bunch of lines at once.
# Note: this test might be a little unreliable.

git init -q "$test_dir"/repo
printf '#!/bin/sh\n\n\nprintf "a\nb\nc\nd\ne\n"\n' > "$test_dir"/repo/.cirun
chmod +x "$test_dir"/repo/.cirun
git -C "$test_dir"/repo add -A
git -C "$test_dir"/repo commit -qm 'Initial commit'
commit=$(git -C "$test_dir"/repo rev-parse HEAD)

"$cirun" run --wait repo "$test_dir"/repo "$commit" 2>&1 | grep -F 'Status: success'
diff -u <("$cirun" log repo 2>&1 | tail -n 8 | tr 0-9 '#') /dev/stdin <<'EOF'
[##:##:## +##:##.###] Process started: './.cirun'
[##:##:## +##:##.###] a
                      b
                      c
                      d
                      e
[##:##:## +##:##.###] Process finished with exit code #
[##:##:## +##:##.###] Job finished with status success
EOF
