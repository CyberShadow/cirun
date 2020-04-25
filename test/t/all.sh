#!/bin/bash
set -eu

# Run all test scripts.

cd "$(dirname "$0")"

for t in ./t-*.sh
do
	printf 'Running test %s:\n' "$t" 1>&2
	$BASH "$t"
done

printf 'All tests OK!\n' 1>&2
