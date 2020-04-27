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
import ae.utils.aa;
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

	enum parseErrorValue = typeof(this).init;
}

// Global

struct GlobalState /// Persistent global state
{
	Job[] jobs; /// Active jobs (with status queued/starting/running)
}

auto getGlobalState() /// ditto
{
	getRoot(Root.data).ensureDirExists;
	return Persistent!GlobalState(getGlobalStatePath());
}

alias HistoryEntry = Job; /// Global/repo/commit history entry (append-only)

auto getGlobalHistoryWriter() { return LogWriter!HistoryEntry(getGlobalHistoryPath()); } /// ditto
auto getGlobalHistoryReader() { return LogReader!HistoryEntry(getGlobalHistoryPath()); } /// ditto

// Repository

auto getRepoHistoryWriter(string repo) { return LogWriter!HistoryEntry(getRepoHistoryPath(repo)); } /// ditto
auto getRepoHistoryReader(string repo) { return LogReader!HistoryEntry(getRepoHistoryPath(repo)); } /// ditto

// Commit

auto getCommitHistoryWriter(string repo, string commit) { return LogWriter!HistoryEntry(getCommitHistoryPath(repo, commit)); } /// ditto
auto getCommitHistoryReader(string repo, string commit) { return LogReader!HistoryEntry(getCommitHistoryPath(repo, commit)); } /// ditto

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

	struct JobStart
	{
		OrderedMap!(string, string) environment;
		string currentDirectory;
	}
	@JSONOptional Nullable!JobStart jobStart;

	struct JobFinish
	{
		JobStatus status;
		string statusText;
	}
	@JSONOptional Nullable!JobFinish jobFinish;

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

	enum parseErrorValue = typeof(this).init;
}

auto getJobLogWriter(string jobID) /// ditto
{
	return LogWriter!JobLogEntry(getJobLogPath(jobID));
}

auto getJobLogReader(string jobID) /// ditto
{
	return LogReader!JobLogEntry(getJobLogPath(jobID));
}
