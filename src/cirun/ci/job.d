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

import std.algorithm.searching;
import std.conv;
import std.datetime.systime;
import std.file;
import std.process;
import std.stdio;

import ae.sys.file;
import ae.utils.path;
import ae.utils.time.format;

import cirun.common.config;
import cirun.common.ids;
import cirun.common.paths;
import cirun.common.state;
import cirun.util.persistence;

struct JobResult
{
	string jobID;
	JobState state;
}

/// Get the state of a job, queuing or starting it if necessary.
/// If retestID is null or the last job for this repo/commit is
/// retestID, start a new job.
JobResult needJob(ref JobSpec spec, string retestID)
{
	{
		auto commitState = getCommitState(spec.repo, spec.commit);
		if (commitState.value.lastJobID && (retestID is null || retestID != commitState.value.lastJobID))
			return getJobResult(commitState.value.lastJobID);
	}

	return queueJob(spec);
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
	auto jobState = getJobState(jobID);
	jobState.value.status = JobStatus.starting;
	jobState.value.startTime = Clock.currTime.stdTime;

	try
	{
		// Note: we keep holding the jobState lock as the process is
		// started until this function exits.
		auto nullFile = File(nullFileName, "r+");
		spawnProcess([thisExePath, "job-runner", jobID],
			nullFile, nullFile, nullFile,
			null,
			std.process.Config.detached,
		);
	}
	catch (Exception e)
	{
		jobState.value.status = JobStatus.errored;
		jobState.value.statusText = e.msg;
		jobState.value.finishTime = Clock.currTime.stdTime;
	}

	// TODO: still-running lock
	// (readln from process to know it's running; fail if readln fails)
	// Is it needed? What about the runner's "pick something from the queue" logic, there's no room for that there

	return JobResult(jobID, jobState.value);
}

JobResult getJobResult(string jobID)
{
	auto jobState = getJobState(jobID);

	// TODO: cleanup if terminated improperly

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
		if (result.state.status == JobStatus.queued && numRunningJobs < config.maxParallelJobs)
		{
			result = startJob(result.jobID);
			if (!result.state.status.isFinished)
				numRunningJobs++;
		}

	globalState.value.jobs = jobs;

	return results;
}
