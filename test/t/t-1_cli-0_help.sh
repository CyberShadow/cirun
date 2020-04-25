#!/bin/bash
source ./lib.bash

# Test --help output.

"$cirun" --help || true

for action in server run status log
do
	printf '\n###############################################################################\n###############################################################################\n\n'
	"$cirun" "$action" --help
done
