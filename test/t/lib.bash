# cirun test suite support code.
# Sourced by test case scripts.

set -eEuo pipefail
shopt -s lastpipe

tmp_dir=/tmp/cirun-test
mkdir -p "$tmp_dir"

# Build
if [[ ! -v CIRUN_BUILT ]]
then
	(
		flock 9
		cd ../..
		dub build -q
	) 9>> "$tmp_dir"/build.lock
	export CIRUN_BUILT=1
fi
cirun=$PWD/../../cirun

test_name=$(basename "$0" .sh)
if [[ "$test_name" != all ]]
then
	test_dir=$tmp_dir/$test_name

	rm -rf "$test_dir"
	mkdir "$test_dir"
	cd "$test_dir"

	{
		printf 'dataDir = cirun-data\n'
		printf 'workDir = cirun-work\n'
	} > cirun.conf
fi
