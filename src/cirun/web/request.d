/**
 * HTTP request handler.
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

module cirun.web.request;

import std.algorithm.searching;
import std.array;
import std.exception;

import ae.net.http.common;
import ae.net.http.responseex;
import ae.sys.dataset;
import ae.sys.log;
import ae.utils.array;

import cirun.common.config;
import cirun.web.common;
import cirun.web.html.pages;
import cirun.web.statics;
import cirun.web.webhook;

void handleRequest(
	HttpRequest request,
	immutable ref Config.Server serverConfig,
	void delegate(HttpResponse) handleResponse,
	ref Logger log,
)
{
	/*
	  There are a few conflicting goals with the possible ways to
	  handle authentication and static resources:

	  - Ideally, error pages (wrong prefix or unauthorized) should be
	    appropriately styled.

	  - Ideally, reusable static resources should be in their own
	    files, and served with an appropriate cache header.

	  - Ideally, visiting a page with an incorrect path prefix should
	    not expose the correct one.

	  From above, choose any two:

	  - We could embed all resources in the HTML page, which will make
	    them self-contained and not expose the correct prefix, but
	    won't work for things like the favicon.

	  - We could not care about error pages and allow them to look
	    broken. Static resources will be available on non-error pages.

	  - We could (try to) always link to the static resources, and
	    make them available to unauthorized users.

	  The approach cirun uses here is to show bare-bones error pages
	  for unauthenticated requests, and appropriately styled ones for
	  authenticated requests.
	 */

	auto response = new HttpResponseEx();
	response.status = HttpStatusCode.OK;
	response.pageTemplate = minimalPageTemplate;

	try
	{
		auto path = request.path;
		path.skipOver(serverConfig.prefix).httpEnforce(HttpStatusCode.NotFound);
		auto pathParts = path.split1("/");

		if ((serverConfig.username || serverConfig.password) &&
			!response.authorize(request, (reqUser, reqPass) =>
				reqUser == serverConfig.username && reqPass == serverConfig.password))
			return handleResponse(response);

		response.pageTemplate = pageTemplate; // Safe to use the full template past this point
		response.pageTokens["static-root"] = "../".replicate(pathParts.length - 1) ~ "static/" ~ staticCacheKey ~ "/";

		switch (pathParts[0])
		{
			case "":
				(pathParts.length == 1).httpEnforce(HttpStatusCode.NotFound);
				(request.method == "GET").httpEnforce(HttpStatusCode.MethodNotAllowed);
				response.serveIndexPage();
				break;
			case "static":
				(pathParts.length >= 3).httpEnforce(HttpStatusCode.NotFound);
				(pathParts[1] == staticCacheKey).httpEnforce(HttpStatusCode.NotFound);
				response.serveStatic(pathParts[2..$].join("/"));
				break;
			case "favicon.ico":
				response.headers["Location"] = "static/" ~ staticCacheKey ~ "/favicon.svg";
				response.status = HttpStatusCode.Found;
				break;
			case "webhook":
				(pathParts.length == 1).httpEnforce(HttpStatusCode.NotFound);
				(request.method == "POST").httpEnforce(HttpStatusCode.MethodNotAllowed);
				(request.headers.get("Content-Type", null) == "application/json").httpEnforce(HttpStatusCode.UnsupportedMediaType);
				processWebhook(cast(string)request.data.joinToHeap());
				response.serveText("OK");
				break;

			default:
				throw new HttpException(HttpStatusCode.NotFound);
		}
	}
	catch (HttpException e)
		response.writeError(e.status, e.msg);
	catch (Exception e)
	{
		log(e.toString());
		response.writeError(HttpStatusCode.InternalServerError, e.msg);
	}
	handleResponse(response);
}
