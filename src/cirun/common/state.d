/**
 * Specification of cirun persistent state.
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

module cirun.common.state;

import std.path;
import std.typecons : Nullable;

import ae.sys.file;
import ae.utils.json : JSONOptional;
import ae.utils.time : StdTime;

import cirun.common.paths;
import cirun.util.persistence;

// Job spec

struct JobSpec /// Specification for a requested job.
{
	string repo; /// incl. namespace, if any
	string cloneURL;
	string commit;
}

struct Job /// Description of a specific job.
{
	JobSpec spec;
	string jobID;
}

// Global

struct GlobalState /// Persistent global state
{
	Job[] jobs; /// Active jobs (with status queued/starting/running)
}

auto getGlobalState() /// ditto
{
	return Persistent!GlobalState(getRoot(Root.data).buildPath("global.json"));
}

alias GlobalHistoryEntry = Job; /// Global history entry (append-only)

auto getGlobalHistoryWriter() /// ditto
{
	return LogWriter!GlobalHistoryEntry(getRoot(Root.data).buildPath("history.json"));
}

auto getGlobalHistoryReader() /// ditto
{
	return LogReader!GlobalHistoryEntry(getRoot(Root.data).buildPath("history.json"));
}

// Commit

struct CommitState /// Persistent per-commit state
{
	string lastJobID;
}

auto getCommitState(string repo, string commit) /// ditto
{
	auto path = getCommitDir(Root.data, repo, commit).buildPath("commit.json");
	ensurePathExists(path);
	return Persistent!CommitState(path);
}

// Job

enum JobStatus
{
	none,      /// Indicates absence of information (job state file not found)
	queued,    /// In queue (due to maxParallelJobs). Never actually occurs in job.json.
	starting,  /// The runner process is starting (very short-lived)
	running,   /// Running right now
	success,   /// Done, success
	failure,   /// Done, failure
	errored,   /// Error occurred outside of the test script
	cancelled, /// Cancelled while queued or running
}

bool isFinished(JobStatus status) /// Returns true if status is terminal
{
	return status >= JobStatus.success;
}

struct JobState /// Persistent per-job state
{
	JobSpec spec;
	JobStatus status;
	string statusText;
	StdTime startTime, finishTime;
}

auto getJobState(string jobID) /// ditto
{
	return Persistent!JobState(getJobDir(Root.data, jobID).buildPath("job.json"));
}

struct JobLogEntry /// Job log entry (append-only)
{
	StdTime time; // Absolute wall clock time (hnsecs since SysTime epoch)
	StdTime elapsed; // Relative monotonic time since job start

	struct ProcessStart
	{
		string[] commandLine;
	}
	@JSONOptional Nullable!ProcessStart processStart;

	struct ProcessFinish
	{
		int exitCode;
	}
	@JSONOptional Nullable!ProcessFinish processFinish;

	struct Data
	{
		enum Stream
		{
			stdout,
			stderr,
		}
		Stream stream;
		string text;
	}
	@JSONOptional Nullable!Data data;
}

auto getJobLogWriter(string jobID) /// ditto
{
	return LogWriter!JobLogEntry(getJobDir(Root.data, jobID).buildPath("log.json"));
}

auto getJobLogReader(string jobID) /// ditto
{
	return LogReader!JobLogEntry(getJobDir(Root.data, jobID).buildPath("log.json"));
}
