/**
 * Static HTTP resources.
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

module cirun.web.statics;

import std.meta;

import ae.net.http.responseex;
import ae.utils.mime;
import ae.utils.text.ascii;
import ae.utils.time.common;
import ae.utils.time.parse;

import cirun.web.common;

void serveStatic(HttpResponseEx response, string path)
{
	alias staticFiles = AliasSeq!("style.css", "favicon.svg");
	switch (path)
	{
		foreach (fn; staticFiles)
		{
			case fn:
				enum mimeType = guessMime(fn);
				response.serveData(import("web/static/" ~ fn), mimeType);
				return;
		}
		default:
			throw new HttpException(HttpStatusCode.NotFound);
	}
}

enum buildTime = __TIMESTAMP__.parseTime!(TimeFormats.CTIME).toUnixTime;
enum staticCacheKey = buildTime.toDec;
