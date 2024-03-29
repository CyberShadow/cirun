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
 *   Vladimir Panteleev <vladimir@cy.md>
 */

module cirun.ci.runner;

import core.thread;
import core.time;

import std.algorithm.iteration;
import std.algorithm.sorting;
import std.array;
import std.conv;
import std.datetime.systime;
import std.exception;
import std.file;
import std.format;
import std.process;
import std.stdio;

import ae.sys.file : readPartial, pushd;
import ae.utils.aa : orderedMap;
import ae.utils.exception;
import ae.utils.json;
import ae.utils.path;
import ae.utils.time;

import cirun.ci.job : setJobStatus, updateJobs, runnerStartLine;
import cirun.common.config;
import cirun.common.paths;
import cirun.common.state;
import cirun.util.persistence : LogWriter;

void runJob(string jobID)
{
	auto runLock = File(getJobRunLockPath(jobID), "ab");
	runLock.lock();

	stdout.writeln(runnerStartLine);
	stdout.flush();

	JobSpec spec;

	setJobStatus(jobID, JobStatus.running, (ref jobState) {
		spec = jobState.spec;
	});

	LogWriter!JobLogEntry logFile;
	auto startTime = MonoTime.currTime;

	void log(JobLogEntry e)
	{
		e.time = Clock.currTime.stdTime;
		e.elapsed = (MonoTime.currTime - startTime).stdTime;
		logFile.put(e);
	}

	void finishJob(JobStatus status, string statusText = null)
	{
		setJobStatus(jobID, status, (ref jobState) {
			jobState.statusText = statusText;
			jobState.finishTime = Clock.currTime.stdTime;
		});
		if (logFile.isOpen)
		{
			JobLogEntry e = { jobFinish : JobLogEntry.JobFinish(status, statusText) };
			log(e);
		}
	}

	try
	{
		logFile = getJobLogWriter(jobID);

		auto repoDir = getJobRepoDir(jobID, spec.repo);

		{
			auto environ = environment.toAA
				.byKeyValue
				.array
				.sort!((a, b) => a.key < b.key)
				.release
				.orderedMap;
			JobLogEntry e = { jobStart : JobLogEntry.JobStart(environ, repoDir) };
			log(e);
		}

		void runProgram(string what, string[] commandLine)
		{
			{
				JobLogEntry e = { processStart : JobLogEntry.ProcessStart(commandLine) };
				log(e);
			}

			auto stdin = File(nullFileName, "rb");
			auto stdout = pipe();
			auto stderr = pipe();

			Pid pid;
			static if (__VERSION__ > 2_094)
			{
				pid = spawnProcess(commandLine,
					stdin, stdout.writeEnd, stderr.writeEnd,
					null, std.process.Config.none, repoDir);
			}
			else
			{
				// Work around https://issues.dlang.org/show_bug.cgi?id=20765
				auto _ = pushd(repoDir);
				pid = spawnProcess(commandLine,
					stdin, stdout.writeEnd, stderr.writeEnd);
			}

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

			enforce!ExitCodeException(exitCode == 0,
				format("%s failed with status %d", what, exitCode));
		}

		auto repoConfig = getRepositoryConfig(spec.repo);

		mkdirRecurse(repoDir);

		runProgram("Clone", repoConfig.cloneCommand ~ [spec.cloneURL, "."]);

		runProgram("Check-out", repoConfig.checkoutCommand ~ [spec.commit]);

		auto command = getCmdLine(repoConfig, repoDir);

		try
		{
			runProgram("CI script", command);
			finishJob(JobStatus.success);
		}
		catch (ExitCodeException e)
			finishJob(JobStatus.failure, e.msg);
	}
	catch (Exception e)
		finishJob(JobStatus.errored, e.msg);

	// Immediately start a new queued job
	getGlobalState().updateJobs();
}

private:

string[] getCmdLine(in ref RepositoryConfig repoConfig, string repoDir)
{
	import std.path : baseName, buildPath;

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

mixin DeclareException!q{ExitCodeException};
