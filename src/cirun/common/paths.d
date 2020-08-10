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
 *   Vladimir Panteleev <vladimir@cy.md>
 */

module cirun.common.paths;

import std.array : replace, split;
import std.exception : enforce;
import std.file : tempDir;
import std.path : buildPath, dirSeparator, dirName;

import ae.sys.process : getCurrentUser;

import cirun.common.config;
import cirun.common.ids;

/// For a possibly-relative path,
/// ensure it's relative to the configuration file's directory.
alias configRelativePath = (string path) =>
	configRoot.dirName.buildPath(path);

string workDir()
{
	if (config.workDir)
		return config.workDir.configRelativePath;
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
			return config.dataDir.configRelativePath;
	}
}

alias getGlobalStatePath = () =>
	getRoot(Root.data).buildPath("global.json");

alias getGlobalHistoryPath = () =>
	getRoot(Root.data).buildPath("history.json");

string getRepoDir(Root root, string repo)
{
	enforce(repo.isRepoID(), "Invalid repository name");
	return getRoot(root).buildPath("repos", repo.replace("/", dirSeparator));
}

alias getRepoHistoryPath = (string repo) =>
	getRepoDir(Root.data, repo).buildPath("history.json");

string getCommitDir(Root root, string repo, string commit)
{
	enforce(commit.isCommitID(), "Invalid commit SHA-1");
	return getRepoDir(root, repo).buildPath(commit[0..2], commit[4..$]);
}

alias getCommitHistoryPath = (string repo, string commit) =>
	getCommitDir(Root.data, repo, commit).buildPath("history.json");

string getJobDir(Root root, string jobID)
{
	enforce(jobID.isJobID(), "Invalid job ID");
	return getRoot(root).buildPath("jobs", jobID[0..8], jobID[8..$]);
}

alias getJobStatePath = (string jobID) =>
	getJobDir(Root.data, jobID).buildPath("job.json");

alias getJobLogPath = (string jobID) =>
	getJobDir(Root.data, jobID).buildPath("log.json");

alias getJobStartLockPath = (string jobID) =>
	getJobDir(Root.work, jobID).buildPath("start.lock");

alias getJobRunLockPath = (string jobID) =>
	getJobDir(Root.work, jobID).buildPath("run.lock");

alias getJobRepoDir = (string jobID, string repo) =>
	getJobDir(Root.work, jobID).buildPath("r", repo.split("/")[$-1]);
