/**
 * Command-Line Interface (entry point and actions).
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

module cirun.cli.cli;

import std.algorithm.searching;
import std.conv;
import std.exception;
import std.file : thisExePath, exists;
import std.stdio;
import std.string;

import ae.utils.funopt;
import ae.utils.meta : structFun;

import cirun.ci.job;
import cirun.ci.runner;
import cirun.cli.term;
import cirun.common.config;
import cirun.common.ids;
import cirun.common.paths;
import cirun.common.state;
import cirun.web.server;

struct CLI
{
static:
	@(`Start cirun as a server.`)
	void server()
	{
		enforce(config.server.length, "No servers are configured.");
		startServers();
	}

	@(`Show information about the last job (starting one if none) for the given repository commit.`)
	void run(
		string repository,
		string cloneURL,
		string commit,
		Switch!"Wait until this job has finished." wait = false,
		Switch!"Do not print the job status." quiet = false,
		Option!(string, "Write job ID to the given file.", "PATH") jobIDFile = null,
	)
	{
		JobSpec spec;
		spec.repo = repository;
		spec.cloneURL = cloneURL;
		spec.commit = commit;
		auto result = needJob(spec, null, wait);
		if (!quiet)
			printJobResult(result);
		if (jobIDFile)
			File(jobIDFile, "wb").writeln(result.jobID);
	}

	@(`Show status. If an ID is specified, show the status of a matching job.`)
	void status(
		Parameter!(string, "A job ID, commit hash, or repository name.") id = null
	)
	{
		if (id)
		{
			auto jobID = resolveJob(id);
			auto result = getJobResult(jobID);
			printJobResult(result);
		}
		else
			printGlobalStatus();
	}

	@(`Show log. If an ID is specified, show the log of a matching job.`)
	void log(
		Parameter!(string, "A job ID, commit hash, or repository name.") id = null
	)
	{
		if (id)
		{
			auto jobID = resolveJob(id);
			printJobLog(jobID);
		}
		else
			printGlobalHistory();
	}

	// Internal
	void jobRunner(string jobID)
	{
		runJob(jobID);
	}
}

/// Accept a "DWIM" ID (job ID or commit hash or repository name), and
/// return a job ID.
string resolveJob(string id)
{
	if (id.isJobID)
	{
		if (getJobDir(Root.data, id).exists)
			return id;
		throw new Exception("Understood " ~ id ~ " to be a job ID, but this job does not exist.");
	}
	else
	if (id.isCommitID)
	{
		foreach (entry; getGlobalHistoryReader().reverseIter)
			if (entry.spec.commit == id)
				return entry.jobID;
		throw new Exception("Understood " ~ id ~ " to be a commit ID, but found no matching job in the history.");
	}
	else
	if (id.isRepoID)
	{
		foreach (entry; getGlobalHistoryReader().reverseIter)
			if (entry.spec.repo == id)
				return entry.jobID;
		throw new Exception("Understood " ~ id ~ " to be a repository name, but found no matching job in the history.");
	}
	else
		throw new Exception("Sorry, I did not understand what " ~ id ~ " might refer to.");
}

void cliEntryPoint()
{
	static void usageFun(string usage)
	{
		import std.path : absolutePath, buildNormalizedPath;

		auto lines = usage.splitLines();

		stderr.writeln("cirun - the minimal CI runner");
		stderr.writeln("Created by Vladimir Panteleev");
		stderr.writeln("https://github.com/CyberShadow/cirun");
		stderr.writeln();
		stderr.writeln("Configuration files: ", configFiles.length ? text(configFiles) : "(none)");
		stderr.writeln("Data directory: ", config.dataDir.absolutePath.buildNormalizedPath);
		stderr.writeln("Working directory: ", workDir.absolutePath.buildNormalizedPath);
		stderr.writeln();

		if (lines[0].canFind("ACTION [ACTION-ARGUMENTS]"))
		{
			lines =
				[lines[0].replace(" ACTION ", " [OPTION]... ACTION ")] ~
				getUsageFormatString!(structFun!Opts).splitLines()[1..$] ~
				lines[1..$];

			stderr.writefln("%-(%s\n%)", lines);
			stderr.writeln();
			stderr.writeln("For help on a specific action, run: cirun ACTION --help");
			stderr.writeln("For more information, see README.md.");
			stderr.writeln();
		}
		else
			stderr.writefln("%-(%s\n%)", lines);
	}

	funoptDispatch!(CLI, FunOptConfig.init, usageFun)([thisExePath] ~ (opts.action ? [opts.action.value] ~ opts.actionArguments : []));
}
