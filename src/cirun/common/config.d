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
 *   Vladimir Panteleev <vladimir@thecybershadow.net>
 */

module cirun.common.config;

import core.runtime;

import std.algorithm.iteration;
import std.array;
import std.exception;
import std.file;
import std.path : globMatch;

static import std.getopt;

import ae.utils.aa;
import ae.utils.funopt;
import ae.utils.meta;
import ae.utils.sini;

struct RepositoryConfig
{
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
		struct Listen
		{
			string addr;
			ushort port;
			string socketPath;
		}
		Listen listen;

		struct SSL
		{
			string cert, key;
		}
		SSL ssl;

		string prefix = "/";
		string username;
		string password;
	}
	Server[string] server;

	OrderedMap!(string, IniFragment!string) repository;
}
immutable Config config;

struct Opts
{
	Option!(string, "Path to the configuration file to use", "PATH", 'f') configFile;
	Option!(string[], "Additional configuration. Equivalent to cirun.conf settings.", "NAME=VALUE", 'c', "config") configLines;

	Parameter!(string, "Action to perform (see list below)") action;
	Parameter!(immutable(string)[]) actionArguments;
}
immutable Opts opts;
immutable string[] configFiles;

shared static this()
{
	alias fun = structFun!Opts;
	enum funOpts = FunOptConfig([std.getopt.config.stopOnFirstNonOption]);
	void usageFun(string) {}
	auto opts = funopt!(fun, funOpts, usageFun)(Runtime.args);

	enum mainConfigFile = "cirun.conf";
	enum sampleConfigFile = mainConfigFile ~ ".sample";
	enum configDir = mainConfigFile ~ ".d";
	enum defaultConfig = import("cirun.conf.sample");
	immutable(string)[] configFiles;

	if (opts.configFile)
	{
		enforce(opts.configFile.exists, "Specified configuration file does not exist: " ~ opts.configFile);
		if (opts.configFile.isDir)
			configFiles ~= opts.configFile.dirEntries("*.conf", SpanMode.depth).map!(de => de.name).array;
		else
			configFiles = [opts.configFile];
	}
	else
	{
		configFiles ~= mainConfigFile;
		if (configDir.exists)
			configFiles ~= configDir.dirEntries("*.conf", SpanMode.depth).map!(de => de.name).array;
	}
	configFiles = configFiles.filter!exists.array;
	.configFiles = configFiles;
	if (!configFiles.length)
	{
		write(sampleConfigFile, defaultConfig);
		throw new Exception("\n" ~
			"Configuration file or directory not found.\n" ~
			"Created " ~ sampleConfigFile ~ ".\n" ~
			"Please edit " ~ sampleConfigFile ~ ", rename it to " ~ mainConfigFile ~ ", and rerun cirun.");
	}

	auto config = loadInis!Config(configFiles);
	opts.configLines.parseIniInto(config);
	.config = cast(immutable)config;

	.opts = cast(immutable)opts;
}

RepositoryConfig getRepositoryConfig(string name)
{
	RepositoryConfig result;
	foreach (mask, ref section; config.repository)
		if (name.globMatch(mask))
			section.deserializeInto(result);
	return result;
}
