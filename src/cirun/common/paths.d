/**
 * Specification of cirun's directory hierarchy.
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

module cirun.common.paths;

import std.array : replace;
import std.exception : enforce;
import std.file : tempDir;
import std.path : buildPath, dirSeparator;

import ae.sys.process : getCurrentUser;

import cirun.common.config;
import cirun.common.ids;

string workDir()
{
	if (config.workDir)
		return config.workDir;
	return tempDir.buildPath("cirun." ~ getCurrentUser());
}

enum Root
{
	work,
	data,
}

string getRoot(Root root)
{
	final switch (root)
	{
		case Root.work:
			return workDir;
		case Root.data:
			return config.dataDir;
	}
}

string getRepoDir(Root root, string repo)
{
	enforce(repo.isRepoID(), "Invalid repository name");
	return getRoot(root).buildPath("repos", repo.replace("/", dirSeparator));
}

string getCommitDir(Root root, string repo, string commit)
{
	enforce(commit.isCommitID(), "Invalid commit SHA-1");
	return getRepoDir(root, repo).buildPath(commit[0..2], commit[4..$]);
}

string getJobDir(Root root, string jobID)
{
	enforce(jobID.isJobID(), "Invalid job ID");
	return getRoot(root).buildPath("jobs", jobID[0..8], jobID[8..$]);
}
