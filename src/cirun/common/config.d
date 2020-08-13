/**
 * cirun configuration parsing.
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

module cirun.common.config;

import core.runtime;

import std.algorithm.iteration;
import std.array;
import std.exception;
import std.file;
import std.format;
import std.parallelism : totalCPUs;
import std.path;
import std.typecons;

static import std.getopt;

import ae.sys.paths;
import ae.utils.aa;
import ae.utils.funopt;
import ae.utils.meta;
import ae.utils.sini;

import cirun.trigger : TriggerConfig;

struct RepositoryConfig
{
	string[] cloneCommand = ["git", "clone"];
	string[] checkoutCommand = ["git", "checkout", "-qf"];
	string script;
	string[] execPrefix;
}

struct Config
{
	string workDir;
	string dataDir = "./cirun-data/";
	string externalUrlPrefix;
	uint maxParallelJobs = uint.max;

	struct Server
	{
		enum Transport
		{
			inet,
			unix,
			stdin,
			accept,
		}
		Transport transport;

		struct Listen
		{
			string addr;
			ushort port;
			string socketPath;
		}
		Listen listen;

		enum Protocol
		{
			http,
			cgi,
			scgi,
			fastcgi,
		}
		Protocol protocol;

		Nullable!bool nph;

		struct SSL
		{
			string cert, key;
		}
		SSL ssl;

		string logDir = "/dev/stderr";
		string prefix = "/";
		string username;
		string password;

		struct WebHook
		{
			enum Type
			{
				none,
				gogs,
				gitea,
				github,
				gitlab,
				bitbucket,
			}
			Type type;

			string secret;
		}
		WebHook[string] webhook;
	}
	OrderedMap!(string, Server) server;

	OrderedMap!(string, IniFragment!string) repository;

	TriggerConfig[string] trigger;
}
immutable Config config;

struct Opts
{
	Option!(string, "Path to the configuration file or directory to use", "PATH", 'f') configFile;
	Option!(string[], "Additional configuration.\nEquivalent to cirun.conf settings.", "NAME=VALUE", 'c', "config") configLines;

	Parameter!(string, "Action to perform (see list below)") action;
	Parameter!(immutable(string)[]) actionArguments;
}
immutable Opts opts;
immutable string configRoot; // file or directory
immutable string[] configFiles;

enum configFileName = "cirun.conf";
enum sampleConfigFileName = configFileName ~ ".sample";
enum defaultConfig = import("cirun.conf.sample");

shared static this()
{
	alias fun = structFun!Opts;
	enum funOpts = FunOptConfig([std.getopt.config.stopOnFirstNonOption]);
	void usageFun(string) {}
	auto opts = funopt!(fun, funOpts, usageFun)(Runtime.args);

	enum configDirName = configFileName ~ ".d";
	immutable(string)[] configFiles;
	bool configRootIsDir;

	if (opts.configFile)
	{
		enforce(opts.configFile.exists, "Specified configuration file does not exist: " ~ opts.configFile);
		configRoot = opts.configFile;
		configRootIsDir = configRoot.isDir;
	}
	else
	{
		auto searchDirs = [
			".",
			] ~ getConfigDirs("cirun") ~ [
			Runtime.args[0].absolutePath().dirName(),
			thisExePath.dirName,
		];
		string programDir = {
			foreach (ref searchDir; searchDirs)
			{
				searchDir = searchDir.absolutePath().buildNormalizedPath();
				auto path = searchDir;
				while (true)
				{
					if (path.buildPath(configDirName).exists || path.buildPath(configFileName).exists)
						return path;
					auto parent = dirName(path);
					if (parent == path)
						break;
					path = parent;
				}
			}
			return null;
		}();
		enforce(programDir || opts.action == "init", format("\n" ~
			"Configuration file or directory not found.\n" ~
			"\n" ~
			"Searched for %s or %s in:\n" ~
			"%-(- %s\n%|%)" ~
			"and parent directories.\n" ~
			"\n" ~
			"Run \"cirun init\" to create a new cirun configuration.\n",
			configFileName, configDirName,
			searchDirs.orderedSet.keys,
		));

		auto configDirPath = programDir.buildPath(configDirName);
		auto configFilePath = programDir.buildPath(configFileName);
		if (!configDirPath.exists)
			configRoot = configFilePath;
		else
		{
			enforce(!configFilePath.exists,"Found both a configuration file (%s) and directory (%s). Only one must exist."
				.format(configFilePath, configDirPath));
			configRoot = configDirPath;
			configRootIsDir = true;
		}
	}

	if (configRootIsDir)
		configFiles ~= configRoot.dirEntries("*.conf", SpanMode.depth).map!(de => de.name).array;
	else
		configFiles = [configRoot];

	configFiles = configFiles.filter!exists.array;
	.configFiles = configFiles;

	auto config = loadInis!Config(configFiles);
	opts.configLines.parseIniInto(config);
	.config = cast(immutable)config;

	.opts = cast(immutable)opts;
}

uint maxParallelJobs()
{
	if (config.maxParallelJobs == uint.max)
		return totalCPUs;
	else
		return config.maxParallelJobs;
}

string externalUrl(string path)
{
	string prefix = config.externalUrlPrefix;
	if (!prefix)
		foreach (name, ref server; config.server)
		{
			import std.socket : Socket;
			import std.conv : to;
			prefix =
				(server.ssl is Config.Server.SSL.init ? "http" : "https") ~
				"://" ~
				Socket.hostName ~
				(server.listen.port ? ":" ~ server.listen.port.to!string : "") ~
				"/";
			break;
		}
	return prefix ? prefix ~ path : null;
}

RepositoryConfig getRepositoryConfig(string name)
{
	RepositoryConfig result;
	foreach (mask, ref section; config.repository)
		if (name.globMatch(mask))
			section.deserializeInto(result);
	return result;
}

/// Return a command-line prefix to use when self-executing,
/// which includes all pertinent configuration,
/// so that the new instance is configured in the same way as this one.
string[] selfCmdLine()
{
	string[] args = [
		thisExePath.absolutePath,
		"-f", configRoot.absolutePath,
	];
	foreach (line; opts.configLines)
		args ~= ["-c", line];
	return args;
}
