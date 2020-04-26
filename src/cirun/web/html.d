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

module cirun.web.html;

import std.algorithm.iteration;
import std.algorithm.sorting;
import std.array;
import std.conv;
import std.range;

import ae.net.http.responseex;
import ae.sys.term;
import ae.utils.appender;
import ae.utils.xml.entities;

import cirun.ci.job;
import cirun.cli.term;
import cirun.common.state;

enum minimalPageTemplate = `<?content?>`;
enum pageTemplate = import("web/page-template.html");

class HTMLTerm : Term
{
	FastAppender!char buffer;

	static HTMLTerm getInstance()
	{
		static HTMLTerm instance;
		if (!instance)
			instance = new HTMLTerm();
		instance.buffer.clear();
		return instance;
	}

	void putHTML(in char[] s)
	{
		flush();
		buffer.put(s);
	}

	void tag(string tag, void delegate() inner)
	{
		flush();
		buffer.put(`<`, tag, `>`);
		inner();
		flush();
		buffer.put(`</`, tag, `>`);
	}

	void flush()
	{
		if (inSpan)
		{
			buffer.put(`</span>`);
			inSpan = false;
		}
	}

protected:
	override void putText(in char[] s)
	{
		buffer.putEncodedEntities(s);
	}

	override void setTextColor(Color c)
	{
		flush();
		if (c != Color.none)
		{
			buffer.put(`<span class="color-`, c.text, `">`);
			inSpan = true;
		}
	}

	override void setBackgroundColor(Color c) { assert(false); }
	override void setColor(Color fg, Color bg) { assert(false); }

private:
	bool inSpan;
}

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
