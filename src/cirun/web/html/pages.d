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
import cirun.common.ids;
import cirun.common.state;
import cirun.web.common;
import cirun.web.html.jobs;
import cirun.web.html.output;

void serveIndexPage(ref HttpContext context)
{
	auto t = HTMLTerm.getInstance(context);

	auto results = getGlobalState().updateJobs();
	t.tag(`p`, {
		t.put("Active jobs: ");
		foreach (g; results.map!(result => result.state.status).array.sort.group)
		{
			t.tag(`b`, { t.put(t.fg(jobStatusColor(g[0])), g[1]); });
			t.put(" ", g[0], ", ");
		}
		t.tag(`b`, { t.put(results.length); });
		t.put(" total");
		t.tag(`br`);
	});

	foreach (ref result; results)
		t.putJobEntry(result);

	t.putBriefHistory(getGlobalHistoryReader.reverseIter, []);

	t.finish("Status");
}

void serveRepoPage(ref HttpContext context, string repo)
{
	(repo.isRepoID).httpEnforce(HttpStatusCode.BadRequest);
	auto t = HTMLTerm.getInstance(context);
	auto history = getRepoHistoryReader(repo);
	t.putLastJob(history.reverseIter);
	t.putBriefHistory(history.reverseIter, ["repo"] ~ repo.split("/"));
	t.finish("Repo " ~ repo);
}

void serveCommitPage(ref HttpContext context, string repo, string commit)
{
	(repo.isRepoID && commit.isCommitID).httpEnforce(HttpStatusCode.BadRequest);
	auto t = HTMLTerm.getInstance(context);
	auto history = getCommitHistoryReader(repo, commit);
	t.putLastJob(history.reverseIter);
	t.putBriefHistory(history.reverseIter, ["commit"] ~ repo.split("/") ~ [commit]);
	t.finish("Commit " ~ commit);
}

void serveJobPage(ref HttpContext context, string jobID)
{
	(jobID.isJobID).httpEnforce(HttpStatusCode.BadRequest);
	auto t = HTMLTerm.getInstance(context);
	auto result = getJobResult(jobID);
	t.putJobDetails(result);
	auto logReader = getJobLogReader(jobID);
	t.putJobLog(logReader.iter);
	// TODO: job log
	t.finish("Job " ~ jobID);
}

void serveGlobalHistory(ref HttpContext context, size_t page)
{
	auto t = HTMLTerm.getInstance(context);
	t.putHistory(getGlobalHistoryReader.reverseIter, page, []);
	t.finish("History");
}

void serveRepoHistory(ref HttpContext context, string repo, size_t page)
{
	(repo.isRepoID).httpEnforce(HttpStatusCode.BadRequest);
	auto t = HTMLTerm.getInstance(context);
	t.putHistory(getRepoHistoryReader(repo).reverseIter, page, ["repo"] ~ repo.split("/"));
	t.finish(repo ~ " - History");
}

void serveCommitHistory(ref HttpContext context, string repo, string commit, size_t page)
{
	(repo.isRepoID && commit.isCommitID).httpEnforce(HttpStatusCode.BadRequest);
	auto t = HTMLTerm.getInstance(context);
	t.putHistory(getCommitHistoryReader(repo, commit).reverseIter, page, ["commit"] ~ repo.split("/") ~ [commit]);
	t.finish(commit ~ " - History");
}
