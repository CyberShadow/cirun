#!/bin/bash
source ./lib.bash

mv cirun.conf{,.initial}

for t in "$test_data_dir"/*.txt
do
	rm -rf cirun-data

	printf '> %s\n' "$(basename "$t")"

	{
		IFS=$' \r' read -r type secret repo clone_url sha1
		{
			read -r _ # Skip request URL in original test
			printf 'POST /webhook/test HTTP/1.1\r\n'
			cat
		} > request.http
	} < "$t"

	{
		cat cirun.conf.initial
		cat <<EOF
maxParallelJobs = 0
[server.wh]
transport=stdin
protocol=http
[server.wh.webhook.test]
type=$type
EOF
		if [[ "$secret" != '-' ]]
		then
			printf 'secret=%s\n' "$secret"
		fi
	} > cirun.conf

	rm -f response.http
	# shellcheck disable=SC2094
	{
		cat request.http
		while [[ ! -s response.http ]]
		do
			sleep 0.1
		done
	} |
		"$cirun" server wh > response.http

	diff -u <(head -1 response.http) <(printf 'HTTP/1.1 200 OK\r\n')

	if [[ -n "$repo" ]]
	then
		printf '%s\n%s\n%s\n' "$repo" "$clone_url" "$sha1" > job-expected.txt
		jq -r '"\(.spec.repo)\n\(.spec.cloneURL)\n\(.spec.commit)"' < cirun-data/jobs/*/*/job.json > job-actual.txt
		diff -u job-expected.txt job-actual.txt
	else
		test ! -e cirun-data/jobs/*/*/job.json
	fi
done
