/**
 * FastCGI request handling.
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

module cirun.web.fastcgi;

import std.exception;
import std.format;

import ae.net.asockets : socketManager;
import ae.net.http.cgi.common;
import ae.net.http.fastcgi.app;
import ae.net.http.common;
import ae.sys.log;

import cirun.common.config;
import cirun.web.request;

enum fastcgiDefaultServerName = "fastcgi";

bool handleImplicitFastCGIServer()
{
	if (!inFastCGI())
		return false;

	startFastCGIServer(fastcgiDefaultServerName,
		"cirun was invoked as a FastCGI application, but no \"%1$s\" server is configured.\n\n" ~
		"Please add a section named [server.%1$s] to %2$s.",
	);
	socketManager.loop();
	return true;
}

void handleExplicitFastCGIServer(string serverName, bool nph)
{
	startFastCGIServer(serverName,
		"Did not find a section named [server.%s] in %s.");
	socketManager.loop();
}

void startFastCGIServer(string serverName, string errorFmt)
{
	auto serverConfig = serverName in config.server;
	enforce(serverConfig, format(errorFmt, serverName, configFileName));

	// TODO: server file logging
	Logger logger;
	logger = consoleLogger("FastCGI-" ~ serverName);
	//logger = nullLogger();

	auto server = new FastCGIResponderServer;
	// TODO: set nph from serverConfig
	server.log = logger;
	server.handleRequest =
		(ref CGIRequest cgiRequest, void delegate(HttpResponse) handleResponse)
		{
			auto request = new CGIHttpRequest(cgiRequest);
			handleRequest(request, *serverConfig, handleResponse, logger);
		};
	server.listen();
}
