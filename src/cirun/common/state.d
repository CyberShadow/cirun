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

auto getGlobalState() { return Persistent!GlobalState(getGlobalStatePath()); } /// ditto

alias GlobalHistoryEntry = Job; /// Global history entry (append-only)

auto getGlobalHistoryWriter() { return LogWriter!GlobalHistoryEntry(getGlobalHistoryPath()); } /// ditto
auto getGlobalHistoryReader() { return LogReader!GlobalHistoryEntry(getGlobalHistoryPath()); } /// ditto

// Commit

struct CommitState /// Persistent per-commit state
{
	string lastJobID;
}

auto getCommitState(string repo, string commit) { return Persistent!CommitState(getCommitStatePath(repo, commit)); } /// ditto

// Job

enum JobStatus
{
	none,      /// Indicates absence of information (job state file not found)
	corrupted, /// Indicates unreadable information (job state file corrupted)
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
	return Persistent!JobState(getJobStatePath(jobID));
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
	return LogWriter!JobLogEntry(getJobLogPath(jobID));
}

auto getJobLogReader(string jobID) /// ditto
{
	return LogReader!JobLogEntry(getJobLogPath(jobID));
}
