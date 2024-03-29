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
 *   Vladimir Panteleev <vladimir@cy.md>
 */

module cirun.cli.cli;

import std.algorithm.searching;
import std.conv;
import std.exception;
import std.file : thisExePath, exists, write;
import std.path;
import std.stdio : stdout, stderr, File;
import std.string;

import ae.sys.term : term;
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
	@(`Write a sample configuration file.`)
	void init()
	{
		enforce(!sampleConfigFileName.exists, "Not overwriting " ~ sampleConfigFileName ~ ".");
		write(sampleConfigFileName, defaultConfig);
		stderr.writeln(
			"Created " ~ sampleConfigFileName ~ ".\n" ~
			"Please edit " ~ sampleConfigFileName ~ " and rename it to " ~ configFileName ~ ".");
	}

	// UI

	@(`Request and show a job for the given repository commit.

If a job for the given commit already exists, show information about that job instead of starting a new one.`)
	void run(
		string repository,
		string commit,
		Option!(string, "Git URL to clone the repository from", "URL") cloneURL,
		Option!(string, "Git ref (pointing to the commit), if any", "NAME", 0, "ref") refName = null,
		Option!(string, "Git ref URL (used in web interface)", "URL") refURL = null,
		Option!(string, "Commit message of the specified commit (shown in web interface)", "MESSAGE") commitMessage = null,
		Option!(string, "Commit author name (shown in web interface)", "NAME") commitAuthorName = null,
		Option!(string, "Commit author email (used in web interface)", "EMAIL") commitAuthorEmail = null,
		Option!(string, "Commit URL (used in web interface)", "AUTHOR") commitURL = null,
		Switch!"Wait until this job has finished." wait = false,
		Switch!"Do not print the job status." quiet = false,
		Option!(string, "Write job ID to the given file.", "PATH") jobIDFile = null,
		Option!(string, "Start a new job if the last job for this commit is this job ID.", "JOB-ID") retest = null,
	)
	{
		JobSpec spec;
		spec.repo = repository;
		spec.commit = commit;
		spec.cloneURL = cloneURL;
		spec.refName = refName;
		spec.refURL = refURL;
		spec.commitMessage = commitMessage;
		spec.commitAuthorName = commitAuthorName;
		spec.commitAuthorEmail = commitAuthorEmail;
		spec.commitURL = commitURL;

		auto result = needJob(spec, retest, wait);
		if (!quiet)
			term.printJobResult(result);
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
				stdout.write(formatJobResult(result, format));
			else
				term.printJobResult(result);
		}
		else
			term.printGlobalStatus();
	}

	@(`Show the log of a matching job.`)
	void log(
		Parameter!(string, "A job ID, commit hash, or repository name.") id,
	)
	{
		auto jobID = resolveJob(id);
		term.printJobLog(jobID);
	}

	@(`Show the job history.

If a repository / commit is specified, show the job history for that object.`)
	void history(
		Parameter!(string, "Repository name.") repo = null,
		Parameter!(string, "Commit hash.") commit = null,
	)
	{
		if (!repo)
			term.printGlobalHistory();
		else
		if (!commit)
			term.printRepoHistory(repo);
		else
			term.printCommitHistory(repo, commit);
	}

	// Integration - Servers

	@(`Start cirun as a server.`)
	void server(
		Parameter!(string, "If set, exclusively start the server with the given configuration section name.", "NAME") serverName = null,
	)
	{
		if (serverName)
			startServer(serverName);
		else
			startServers();
	}

	// Utility

	@(`Install a git hook in the given repository which invokes cirun in response to specific actions.`)
	void installGitHook(
		Parameter!(string, "The kind of hook to install (post-commit, pre-push, post-receive, or update).") kind,
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
	if (!opts.action)
		if (runImplicitServer())
			return;

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
