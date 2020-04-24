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

import cirun.common.config;
import cirun.web.webhook;

void handleRequest(
	HttpRequest request,
	immutable ref Config.Server serverConfig,
	void delegate(HttpResponse) handleResponse,
	ref Logger log,
)
{
	auto response = new HttpResponseEx();

	if ((serverConfig.username || serverConfig.password) &&
		!response.authorize(request, (reqUser, reqPass) =>
			reqUser == serverConfig.username && reqPass == serverConfig.password))
		return handleResponse(response);

	response.status = HttpStatusCode.OK;

	try
	{
		auto path = request.path;
		path.skipOver(serverConfig.prefix).httpEnforce(HttpStatusCode.NotFound);
		auto pathParts = path.split("/");
		if (!pathParts.length)
			pathParts = [""]; // TODO index
		switch (pathParts[0])
		{
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

class HttpException : Exception
{
	HttpStatusCode status;
	this(HttpStatusCode status, string msg = null) { this.status = status; super(msg); }
}
T httpEnforce(T)(T val, HttpStatusCode status, string msg = null) { return enforce(val, new HttpException(status, msg)); }
