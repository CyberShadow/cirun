/**
 * Job runner (subprocess).
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

module cirun.ci.runner;

import core.thread;
import core.time;

import std.algorithm.iteration;
import std.array;
import std.conv;
import std.datetime.systime;
import std.exception;
import std.file;
import std.format;
import std.path;
import std.process;
import std.stdio;

import ae.sys.file : readPartial;
import ae.utils.json;
import ae.utils.path;
import ae.utils.time;

import cirun.ci.job : updateJobs, runnerStartLine;
import cirun.common.config;
import cirun.common.paths;
import cirun.common.state;

void runJob(string jobID)
{
	auto runLock = File(getJobDir(Root.work, jobID).buildPath("run.lock"), "ab");
	runLock.lock();

	stdout.writeln(runnerStartLine);
	stdout.flush();

	JobSpec spec;

	getJobState(jobID).edit((ref jobState) {
		spec = jobState.spec;
		jobState.status = JobStatus.running;
	});

	void finishJob(JobStatus status, string statusText = null)
	{
		getJobState(jobID).edit((ref jobState) {
			jobState.status = status;
			jobState.statusText = statusText;
			jobState.finishTime = Clock.currTime.stdTime;
		});
	}

	try
	{
		auto jobDataDir = getJobDir(Root.data, jobID);
		auto logFile = File(jobDataDir.buildPath("log.json"), "wb");
		auto startTime = MonoTime.currTime;

		void log(JobLogEntry e)
		{
			e.time = Clock.currTime.stdTime;
			e.elapsed = (MonoTime.currTime - startTime).stdTime;
			logFile.writeln(e.toJson);
			logFile.flush();
		}

		auto repoDir = getJobDir(Root.work, jobID).buildPath("r", spec.repo.baseName);

		void runProgram(string what, string[] commandLine)
		{
			{
				JobLogEntry e = { processStart : JobLogEntry.ProcessStart(commandLine) };
				log(e);
			}

			auto stdin = File(nullFileName, "rb");
			auto stdout = pipe();
			auto stderr = pipe();

			auto pid = spawnProcess(commandLine,
				stdin, stdout.writeEnd, stderr.writeEnd,
				null, std.process.Config.none, repoDir);

			void monitor(File f, JobLogEntry.Data.Stream stream)
			{
				f.setvbuf(0, _IONBF);
				void[4096] buf = void;
				while (true)
				{
					auto readBuf = f.readPartial(buf);
					if (!readBuf.length)
						break;
					JobLogEntry e = { data : JobLogEntry.Data(stream, cast(string)readBuf) };
					// Note: we don't need to synchronize access to
					// the log between threads because of its use of
					// lockingBinaryWriter.
					log(e);
				}
			}
			Thread[2] monitors = [
				new Thread({ monitor(stdout.readEnd, JobLogEntry.Data.Stream.stdout); }),
				new Thread({ monitor(stderr.readEnd, JobLogEntry.Data.Stream.stderr); }),
			];
			monitors.each!(thread => thread.start());
			monitors.each!(thread => thread.join());

			auto exitCode = pid.wait();

			{
				JobLogEntry e = { processFinish : JobLogEntry.ProcessFinish(exitCode) };
				log(e);
			}

			enforce(exitCode == 0,
				format("%s failed with status %d", what, exitCode));
		}

		auto repoConfig = getRepositoryConfig(spec.repo);

		mkdirRecurse(repoDir);

		runProgram("Clone", ["git", "clone", spec.cloneURL, "."]);

		runProgram("Check-out", ["git", "checkout", spec.commit]);

		auto command = getCmdLine(repoConfig, repoDir);

		try
		{
			runProgram("CI script", command);
			finishJob(JobStatus.success);
		}
		catch (Exception e)
			finishJob(JobStatus.failure, e.msg);
	}
	catch (Exception e)
		finishJob(JobStatus.errored, e.msg);

	// Immediately start a new queued job
	getGlobalState().updateJobs();
}

string[] getCmdLine(in ref RepositoryConfig repoConfig, string repoDir)
{
	string script;
	if (repoConfig.script)
		script = repoConfig.script;
	else
	{
		auto candidates = repoDir.dirEntries("{,.}cirun{,.*}", SpanMode.shallow).array;
		if (!candidates.length)
			throw new Exception("No cirun script found or configured");
		if (candidates.length > 1)
			throw new Exception("Multiple cirun script found: " ~ text(candidates));
		script = candidates[0].baseName;
	}
	version (Posix)
		script = buildPath(".", script);
	return [] ~ repoConfig.execPrefix ~ script;
}
