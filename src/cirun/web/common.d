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

import std.exception;

import ae.net.http.common;

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
