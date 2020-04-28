/**
 * Common HTTP code.
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

module cirun.web.common;

import std.array;
import std.exception;

import ae.net.http.common;
import ae.net.http.responseex;

class HttpException : Exception
{
	HttpStatusCode status;

	this(HttpStatusCode status, string msg = null)
	{
		this.status = status;
		super(msg);
	}
}

T httpEnforce(T)(T val, HttpStatusCode status, string msg = null)
{
	return enforce(val, new HttpException(status, msg));
}

struct HttpContext
{
	HttpResponseEx response;
	string[] path;

	string relPath(string[] target...)
	{
		assert(this.path.length > 0);

		auto source = this.path;
		while (source.length > 1 && target.length > 1 && source[0] == target[0])
		{
			source = source[1..$];
			target = target[1..$];
		}
		while (source.length > 1)
		{
			source = source[1..$];
			target = [".."] ~ target;
		}
		return target.join("/");
	}
}
