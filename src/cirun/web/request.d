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
import std.conv;
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

	HttpContext context;
	context.response = new HttpResponseEx();
	context.response.status = HttpStatusCode.OK;
	context.response.pageTemplate = minimalPageTemplate;

	try
	{
		auto path = request.path;
		path.skipOver(serverConfig.prefix).httpEnforce(HttpStatusCode.NotFound);
		auto pathParts = path.split1("/");

		if ((serverConfig.username || serverConfig.password) &&
			!context.response.authorize(request, (reqUser, reqPass) =>
				reqUser == serverConfig.username && reqPass == serverConfig.password))
			return handleResponse(context.response);

		context.response.pageTemplate = pageTemplate; // Safe to use the full template past this point
		context.path = pathParts;
		context.response.pageTokens["root"] = context.relPath("");
		context.response.pageTokens["static-root"] = context.relPath("static", staticCacheKey, "");

		switch (pathParts[0])
		{
			case "":
				(pathParts.length == 1).httpEnforce(HttpStatusCode.NotFound);
				context.serveIndexPage();
				break;
			case "repo":
				(pathParts.length > 2 && pathParts[$-1] == "").httpEnforce(HttpStatusCode.NotFound);
				context.serveRepoPage(pathParts[1..$-1].join("/"));
				break;
			case "commit":
				(pathParts.length > 3 && pathParts[$-1] == "").httpEnforce(HttpStatusCode.NotFound);
				context.serveCommitPage(pathParts[1..$-2].join("/"), pathParts[$-2]);
				break;
			case "job":
				(pathParts.length == 3 && pathParts[$-1] == "").httpEnforce(HttpStatusCode.NotFound);
				context.serveJobPage(pathParts[1]);
				break;
			case "history":
				(pathParts.length > 1 && pathParts[$-1] == "").httpEnforce(HttpStatusCode.NotFound);
				auto page = request.urlParameters.get("page", "0").to!size_t;
				switch (pathParts[1])
				{
				case "":
					(pathParts.length == 2).httpEnforce(HttpStatusCode.NotFound);
					context.serveGlobalHistory(page);
					break;
				case "repo":
					context.serveRepoHistory(pathParts[2..$-1].join("/"), page);
					break;
				case "commit":
					context.serveCommitHistory(pathParts[2..$-2].join("/"), pathParts[$-2], page);
					break;
				default:
					throw new HttpException(HttpStatusCode.NotFound);
				}
				break;
			case "static":
				(pathParts.length >= 3).httpEnforce(HttpStatusCode.NotFound);
				(pathParts[1] == staticCacheKey).httpEnforce(HttpStatusCode.NotFound);
				context.serveStatic(pathParts[2..$].join("/"));
				break;
			case "favicon.ico":
				context.response.headers["Location"] = "static/" ~ staticCacheKey ~ "/favicon.svg";
				context.response.status = HttpStatusCode.Found;
				break;
			case "webhook":
				(pathParts.length == 1).httpEnforce(HttpStatusCode.NotFound);
				(request.method == "POST").httpEnforce(HttpStatusCode.MethodNotAllowed);
				(request.headers.get("Content-Type", null) == "application/json").httpEnforce(HttpStatusCode.UnsupportedMediaType);
				processWebhook(cast(string)request.data.joinToHeap());
				context.response.serveText("OK");
				break;

			// HTTP test endpoint for test suite
			debug
			{
			case "ping":
				(pathParts.length == 1).httpEnforce(HttpStatusCode.NotFound);
				context.response.serveText("pong\n");
				break;
			}

			default:
				throw new HttpException(HttpStatusCode.NotFound);
		}
	}
	catch (HttpException e)
		context.response.writeError(e.status, e.msg);
	catch (Exception e)
	{
		log(e.toString());
		context.response.writeError(HttpStatusCode.InternalServerError, e.msg);
	}
	handleResponse(context.response);
}
