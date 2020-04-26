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
import std.path;
import std.stdio;
import std.string;

import ae.utils.funopt;
import ae.utils.meta : structFun;

import cirun.ci.job;
import cirun.ci.runner;
import cirun.cli.githook;
import cirun.cli.term;
import cirun.common.config;
import cirun.common.ids;
import cirun.common.job.format;
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

	@(`Request and show a job for the given repository commit.

If a job for the given commit already exists, show information about that job instead of starting a new one.`)
	void run(
		string repository,
		string cloneURL, // TODO: figure out if this should be a parameter or option
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
			(jobIDFile == "-" ? stdout : File(jobIDFile, "wb")).writeln(result.jobID);
	}

	@(`Show status.

If an ID is specified, show the status of a matching job.`)
	void status(
		Parameter!(string, "A job ID, commit hash, or repository name.") id = null,
		Option!(string, `Print information in the given format.
The syntax is as follows:
  %j  - Job ID
  %r  - Repository name
  %c  - Commit hash
  %s  - Status
  %S  - Status text
  %bs - Start time  (hectonanoseconds from midnight,
                     January 1st, 1 A.D. UTC)
  %es - Finish time (hectonanoseconds from midnight,
                     January 1st, 1 A.D. UTC)
  %%  - Literal %`, null, 'c') format = null,
	)
	{
		if (id)
		{
			auto jobID = resolveJob(id);
			auto result = getJobResult(jobID);
			if (format)
				formatJobResult(result, format).write;
			else
				printJobResult(result);
		}
		else
			printGlobalStatus();
	}

	@(`Show log.

If an ID is specified, show the log of a matching job.`)
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

	@(`Install a git hook in the given repository which invokes cirun in response to specific actions.`)
	void installGitHook(
		Parameter!(string, "The kind of hook to install (post-commit, pre-push, or post-receive).") kind,
		Parameter!(string, "The path to the repository where the hook will be installed.\nDefaults to the current directory.") repositoryPath = ".",
		Parameter!(string, "The name of the repository to use.\nDefaults to the repository's directory name.") repositoryName = null,
	)
	{
		if (!repositoryName)
			repositoryName = repositoryPath.absolutePath.buildNormalizedPath.baseName;
		.installGitHook(kind, repositoryPath, repositoryName);
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

		stderr.writeln("cirun - the stand-alone CI runner");
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
