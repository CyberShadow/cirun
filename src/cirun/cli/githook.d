/**
 * Installation of git hooks.
 *
 * License:
 *   This Source Code Form is subject to the terms of
 *   the Mozilla Public License, v. 2.0. If a copy of
 *   the MPL was not distributed with this file, You
 *   can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * Authors:
 *   Vladimir Panteleev <vladimir@thecybershadow.net>
 */

module cirun.cli.githook;

import std.algorithm.iteration;
import std.array;
import std.conv : octal;
import std.exception;
import std.file;
import std.path;
import std.string;

import ae.sys.cmd;

import cirun.common.config;

void installGitHook(string kind, string repositoryPath, string repositoryName)
{
	// Do this first to validate the hook kind
	auto hookScript = genHookScript(kind, repositoryName);

	auto hookDir = query(["git", "-C", repositoryPath, "rev-parse", "--git-path", "hooks"]).chomp();
	hookDir = repositoryPath.buildPath(hookDir);

	auto hookPath = hookDir.buildPath(kind);
	enforce(!hookPath.exists, "The hook " ~ hookPath ~ " already exists.");

	write(hookPath, hookScript);
	version (Posix)
		hookPath.setAttributes(hookPath.getAttributes | octal!111); // +x
}

private:

string genHookScript(string kind, string repositoryName)
{
	switch (kind)
	{
		case "post-commit":
			return q"EOF
#!/bin/sh
#
# Git post-commit hook to trigger a cirun job.
# Auto-generated by cirun.

commit=$(git rev-parse HEAD)
git_dir=$(git rev-parse --absolute-git-dir)
exec %-(%s %) run --quiet %s "$git_dir" "$commit"
EOF"
				.format(
					selfCmdLine.map!escapePosixShellArgument,
					repositoryName.escapePosixShellArgument,
				);
		case "pre-push":
			return q"EOF
#!/bin/sh
#
# Git pre-push hook to check cirun status.
# Forbids pushing unless the cirun job for the pushed ref succeeded.
# Auto-generated by cirun.

git_dir=$(git rev-parse --absolute-git-dir)
while read -r local_ref local_sha1 remote_ref remote_sha1
do
	printf -- 'Checking cirun status for %%s (%%s)...\n' "$local_ref" "$local_sha1" 1>&2
	job_id=$(%1$-(%s %) run --quiet --wait --job-id-file=- %2$s "$git_dir" "$local_sha1")
	status=$(%1$-(%s %) status "$job_id" --format=%%s)
	if [ "$status" != success ]
	then
		%1$-(%s %) status "$job_id"
		exit 1
	fi
done
EOF"
				.format(
					selfCmdLine.map!escapePosixShellArgument.array,
					repositoryName.escapePosixShellArgument,
				);
		default:
			throw new Exception("Unknown hook kind");
	}
}

string escapePosixShellArgument(string arg)
{
	return `'` ~ replace(arg, `'`, `'\''`) ~ `'`;
}
