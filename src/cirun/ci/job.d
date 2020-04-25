/**
 * Job control.
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

module cirun.ci.job;

import std.algorithm.comparison;
import std.algorithm.searching;
import std.conv;
import std.datetime.systime;
import std.exception;
import std.file;
import std.process;
import std.stdio;
import std.string;

import ae.sys.file;
import ae.utils.path;
import ae.utils.time.format;

import cirun.common.config;
import cirun.common.ids;
import cirun.common.paths;
import cirun.common.state;
import cirun.util.persistence;

enum runnerStartLine = "ci-run runner OK";

struct JobResult
{
	string jobID;
	JobState state;
}

/// Get the state of a job, queuing or starting it if necessary.
/// If retestID is null or the last job for this repo/commit is
/// retestID, start a new job.
JobResult needJob(ref JobSpec spec, string retestID, bool wait)
{
	getCommitStatePath(spec.repo, spec.commit).ensurePathExists();
	{
		auto commitState = getCommitState(spec.repo, spec.commit);
		if (commitState.value.lastJobID && (retestID is null || retestID != commitState.value.lastJobID))
			return getJobResult(commitState.value.lastJobID);
	}

	auto result = queueJob(spec);

	if (wait)
	{
		auto runLock = File(getJobRunLockPath(result.jobID), "rb");
		runLock.lock(LockType.read);
		result = getJobResult(result.jobID);
	}

	return result;
}

/// Allocate a new unique job ID.
string allocateJobID()
{
	string jobID, jobDataDir;

	// Try creating a directory named after the current time until we succeed.
	do
	{
		jobID = Clock.currTime.formatTime!jobIDTimeFormat;
		jobDataDir = getJobDir(Root.data, jobID);
		ensurePathExists(jobDataDir);
	}
	while (!collectFileExistsError({ mkdir(jobDataDir); }));

	return jobID;
}

/// Allocate a job ID and start / queue a job.
private JobResult queueJob(ref JobSpec spec)
{
	string jobID;

	auto globalState = getGlobalState();
	{
		auto commitState = getCommitState(spec.repo, spec.commit);

		jobID = allocateJobID();
		{
			auto jobState = getJobState(jobID);
			jobState.value.spec = spec;
			jobState.value.status = JobStatus.queued;
		}

		commitState.value.lastJobID = jobID;
	}

	auto job = Job(spec, jobID);
	globalState.value.jobs ~= job;

	auto results = globalState.updateJobs();

	// globalState.save();
	getGlobalHistoryWriter.put(job);

	foreach (ref result; results)
		if (result.jobID == jobID)
			return result;

	assert(false);
}

/// Start a runner for this job now.
private JobResult startJob(string jobID)
{
	mkdirRecurse(getJobDir(Root.work, jobID));
	auto startLock = File(getJobStartLockPath(jobID), "ab");
	startLock.lock();

	JobResult result;
	result.jobID = jobID;

	getJobState(jobID).edit((ref value) {
		value.status = JobStatus.starting;
		value.startTime = Clock.currTime.stdTime;
		result.state = value;
	});

	try
	{
		auto p = pipe();
		auto nullFile = File(nullFileName, "r+");
		spawnProcess([thisExePath, "job-runner", jobID],
			nullFile, p.writeEnd, nullFile,
			null,
			std.process.Config.detached,
		);
		enforce(p.readEnd.readln().chomp() == runnerStartLine, "Unexpected line from runner process");
	}
	catch (Exception e)
	{
		getJobState(jobID).edit((ref value) {
			value.status = JobStatus.errored;
			value.statusText = e.msg;
			value.finishTime = Clock.currTime.stdTime;
			result.state = value;
		});
	}

	return result;
}

JobResult getJobResult(string jobID)
{
	auto jobState = getJobState(jobID);

	if (jobState.value.status.among(JobStatus.starting, JobStatus.running))
	{
		if (!getJobDir(Root.work, jobID).exists)
		{
			jobState.value.status = JobStatus.errored;
			jobState.value.statusText = "job work directory disappeared";
		}
		else
		{
			auto startLock = File(getJobStartLockPath(jobID), "a+b");
			if (startLock.tryLock(LockType.read))
			{
				auto runLock = File(getJobRunLockPath(jobID), "a+b");
				if (runLock.tryLock(LockType.read))
				{
					jobState.value.status = JobStatus.errored;
					jobState.value.statusText = "job runner process did not exit gracefully";
				}
			}
		}
	}

	return JobResult(jobID, jobState.value);
}

/// Clean up finished jobs and start queued jobs.
JobResult[] updateJobs(Persistent!GlobalState globalState)
{
	JobResult[] results;
	Job[] jobs;

	size_t numRunningJobs;
	foreach (ref job; globalState.value.jobs)
	{
		auto result = getJobResult(job.jobID);
		results ~= result;
		if (!result.state.status.isFinished)
		{
			jobs ~= job;
			if (result.state.status != JobStatus.queued) // starting or running
				numRunningJobs++;
		}
	}

	foreach (ref result; results)
		if (result.state.status == JobStatus.queued && numRunningJobs < maxParallelJobs)
		{
			result = startJob(result.jobID);
			if (!result.state.status.isFinished)
				numRunningJobs++;
		}

	globalState.value.jobs = jobs;

	return results;
}
