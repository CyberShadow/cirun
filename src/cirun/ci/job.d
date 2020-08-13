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
 *   Vladimir Panteleev <vladimir@cy.md>
 */

module cirun.ci.job;

import std.algorithm.comparison;
import std.algorithm.iteration;
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
import cirun.trigger;
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
	JobResult result;
	getCommitHistoryPath(spec.repo, spec.commit).ensurePathExists();
	{
		auto repoHistoryWriter = getRepoHistoryWriter(spec.repo);
		auto commitHistoryWriter = getCommitHistoryWriter(spec.repo, spec.commit);
		auto commitHistoryReader = getCommitHistoryReader(spec.repo, spec.commit);
		{
			auto commitHistory = commitHistoryReader.reverseIter().filter!(e => e.jobID);
			if (!commitHistory.empty && (retestID is null || retestID != commitHistory.front.jobID))
				return getJobResult(commitHistory.front.jobID);
		}

		result = queueJob(spec);
		auto job = Job(spec, result.jobID);
		commitHistoryWriter.put(job);
		repoHistoryWriter.put(job);
	}

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

void setJobStatus(string jobID, JobStatus newStatus, scope void delegate(ref JobState state) otherChanges = (ref JobState jobState) {})
{
	JobSpec spec;
	getJobState(jobID).edit((ref value) {
		value.status = newStatus;
		otherChanges(value);
		spec = value.spec;
	});

	TriggerEvent event;
	final switch (newStatus)
	{
		case JobStatus.none     : assert(false);
		case JobStatus.corrupted: assert(false);
		case JobStatus.queued   : event.type = TriggerEvent.Type.queued;    break;
		case JobStatus.starting : event.type = TriggerEvent.Type.starting;  break;
		case JobStatus.running  : event.type = TriggerEvent.Type.running;   break;
		case JobStatus.success  : event.type = TriggerEvent.Type.succeeded; break;
		case JobStatus.failure  : event.type = TriggerEvent.Type.failed;    break;
		case JobStatus.errored  : event.type = TriggerEvent.Type.errored;   break;
		case JobStatus.cancelled: event.type = TriggerEvent.Type.cancelled; break;
	}
	event.job = Job(spec, jobID);
	runTriggers(event);

	if (spec.refName && newStatus.among(JobStatus.success, JobStatus.failure, JobStatus.errored))
	{
		JobStatus oldStatus;
		{
			auto repoState = getRepoState(spec.repo);
			oldStatus = repoState.value.previousRefState.get(spec.refName, JobStatus.none);
			repoState.value.previousRefState[spec.refName] = newStatus;
		}

		if (oldStatus.among(JobStatus.success) && newStatus.among(JobStatus.failure, JobStatus.errored))
		{
			event.type = TriggerEvent.Type.broken;
			runTriggers(event);
		}
		else
		if (oldStatus.among(JobStatus.failure, JobStatus.errored) && newStatus.among(JobStatus.success))
		{
			event.type = TriggerEvent.Type.fixed;
			runTriggers(event);
		}
		else
		if (oldStatus == JobStatus.none && newStatus.among(JobStatus.success))
		{
			event.type = TriggerEvent.Type.createSuccess;
			runTriggers(event);
		}
		else
		if (oldStatus == JobStatus.none && newStatus.among(JobStatus.failure, JobStatus.errored))
		{
			event.type = TriggerEvent.Type.createFailure;
			runTriggers(event);
		}
	}
}

/// Allocate a job ID and start / queue a job.
private JobResult queueJob(ref JobSpec spec)
{
	string jobID;

	auto globalState = getGlobalState();
	{
		jobID = allocateJobID();
		setJobStatus(jobID, JobStatus.queued, (ref jobState) { jobState.spec = spec; });
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

	setJobStatus(jobID, JobStatus.starting, (ref jobState) {
		jobState.startTime = Clock.currTime.stdTime;
		result.state = jobState;
	});

	try
	{
		auto p = pipe();
		auto nullFile = File(nullFileName, "r+");
		spawnProcess(selfCmdLine ~ ["job-runner", jobID],
			nullFile, p.writeEnd, stderr,
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
	Persistent!JobState jobState;
	try
		if (!{ jobState = getJobState(jobID); }.collectNotFoundError)
			return JobResult(jobID, JobState(JobSpec.init, JobStatus.none));
	catch (Exception e)
		return JobResult(jobID, JobState(JobSpec.init, JobStatus.corrupted, e.msg));

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

JobResult getJobResult(HistoryEntry job)
{
	if (job is Job.parseErrorValue)
		return JobResult(null, JobState(JobSpec.init, JobStatus.corrupted, "(corrupted history entry)"));
	else
		return getJobResult(job.jobID);
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
