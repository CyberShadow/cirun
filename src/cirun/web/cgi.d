/**
 * CGI request handling.
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

module cirun.web.cgi;

import std.exception;
import std.format;

import ae.net.http.cgi.common;
import ae.net.http.cgi.script;
import ae.net.http.common;
import ae.sys.log;

import cirun.common.config;
import cirun.web.request;

enum cgiDefaultServerName = "cgi";

bool handleImplicitCGIRequest()
{
	if (!inCGI())
		return false;

	handleCGIRequest(cgiDefaultServerName, isNPH(),
		"cirun was invoked as a CGI script, but no \"%1$s\" server is configured.\n\n" ~
		"Please add a section named [server.%1$s] to %2$s.",
	);
	return true;
}

void handleExplicitCGIRequest(string serverName, bool nph)
{
	handleCGIRequest(serverName, nph,
		"Did not find a section named [server.%s] in %s.");
}

void handleCGIRequest(string serverName, bool nph, string errorFmt)
{
	auto serverConfig = serverName in config.server;
	enforce(serverConfig, format(errorFmt, serverName, configFileName));
	auto cgiRequest = readCGIRequest();
	auto request = new CGIHttpRequest(cgiRequest);

	bool responseWritten;
	void handleResponse(HttpResponse response)
	{
		if (nph)
			writeNPHResponse(response);
		else
			writeCGIResponse(response);
		responseWritten = true;
	}

	Logger logger;
	logger = consoleLogger("CGI-" ~ serverName);
	handleRequest(request, *serverConfig, &handleResponse, logger);
	assert(responseWritten);
}
