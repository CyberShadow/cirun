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

import std.array : replace;
import std.file;
import std.meta;
import std.path;

import ae.net.http.responseex;
import ae.utils.mime;
import ae.utils.text.ascii;
import ae.utils.time.common;
import ae.utils.time.parse;

import cirun.web.common;

debug string srcDir()
{
	if (__FILE__.isAbsolute)
		return __FILE__.dirName.dirName.dirName;
	else
		return thisExePath.dirName.buildPath("src");
}

enum minimalPageTemplate = `<?content?>`;
debug
	@property string pageTemplate() { return srcDir.buildPath("web", "page-template.html").readText; }
else
	enum pageTemplate = import("web/page-template.html");

void serveStatic(ref HttpContext context, string path)
{
	debug
	{
		context.response.serveFile(path, srcDir.buildPath("web", "static") ~ dirSeparator);
	}
	else
	{
		context.response.cacheForever();
		alias staticFiles = AliasSeq!("style.css", "favicon.svg", "icons.min.svg");
		switch (path)
		{
			foreach (fn; staticFiles)
			{
				case fn.replace(".min.", "."):
					enum mimeType = guessMime(fn);
					context.response.serveData(import("web/static/" ~ fn), mimeType);
					return;
			}
			default:
				throw new HttpException(HttpStatusCode.NotFound);
		}
	}
}

enum buildTime = __TIMESTAMP__.parseTime!(TimeFormats.CTIME).toUnixTime;
enum staticCacheKey = buildTime.toDec;
