/**
 * HTML webpage generation.
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

module cirun.web.html.pages;

import std.algorithm.iteration;
import std.algorithm.sorting;
import std.array;
import std.conv;
import std.datetime.systime;
import std.range;

import ae.net.http.responseex;
import ae.sys.term;
import ae.utils.appender;
import ae.utils.time;
import ae.utils.xml.entities;

import cirun.ci.job;
import cirun.cli.term;
import cirun.common.state;
import cirun.web.html.output;

enum minimalPageTemplate = `<?content?>`;
enum pageTemplate = import("web/page-template.html");

void serveIndexPage(HttpResponseEx response)
{
	auto t = HTMLTerm.getInstance();

	auto results = getGlobalState().updateJobs();
	t.tag(`pre`, {
		t.put("Jobs: ");
		foreach (g; results.map!(result => result.state.status).array.sort.group)
			t.put(t.fg(jobStatusColor(g[0])), g[1], t.none, " ", g[0], ", ");
		t.put(results.length, " total\n");

		foreach (result; results)
			t.printJobSummary(result);

		enum numHistoryEntries = 10;
		t.put("\nLast ", numHistoryEntries, " jobs:\n");
		t.printGlobalHistory(getGlobalHistoryReader.reverseIter.take(numHistoryEntries));
	});

	response.writePageContents("Status", cast(string)t.buffer.get);
}
