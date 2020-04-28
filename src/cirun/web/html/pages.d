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

enum historyPageSize = 10;

void putBriefHistory(R)(HTMLTerm t, R jobs, string[] object)
{
	t.tag(`h2`, { t.put("History"); });
	t.putHistory(jobs, 0, object);
}

void putHistory(R)(HTMLTerm t, R jobs, size_t page, string[] object)
{
	size_t numEntries;
	jobs = jobs.drop(page * historyPageSize);
	if (jobs.empty && page > 0)
		throw new HttpException(HttpStatusCode.NotFound);
	while (!jobs.empty && numEntries < historyPageSize)
	{
		t.putJobEntry(jobs.front.getJobResult());
		numEntries++;
		jobs.popFront();
	}
	if (!numEntries)
		t.tag(`p`, {
			t.put(`No entries.`);
		});
	if (page > 0)
		t.tag(`a`, [
			"class" : "page-prev",
			"href" : text(t.context.relPath(["history"] ~ object ~ [""]), "?page=", page - 1),
		], { t.put("Newer"); });
	if (!jobs.empty)
		t.tag(`a`, [
			"class" : "page-next",
			"href" : text(t.context.relPath(["history"] ~ object ~ [""]), "?page=", page + 1),
		], { t.put("Older"); });
}

void putJobEntry(HTMLTerm t, JobResult result)
{
	t.tag(`div`, ["class" : "job-box summary status-" ~ result.state.status.text], {
		t.tag(`div`, {
			t.putRepoID(result.state.spec);
			t.putCommitID(result.state.spec);
		});

		t.tag(`div`, {
			t.putJobID(result.jobID);
			t.putJobStatus!false(result.state);
		});

		t.tag(`div`, {
			t.putDate!false(result.state.startTime);
			t.putDuration(result.state.startTime, result.state.finishTime);
		});
	});
}

void putLastJob(R)(HTMLTerm t, R iter)
{
	if (iter.empty)
		t.tag(`p`, {
			t.put(`No jobs.`);
		});
	else
		t.putJobDetails(iter.front.getJobResult());
}

void putJobDetails(HTMLTerm t, JobResult result)
{
	t.tag(`div`, ["class" : "job-box details status-" ~ result.state.status.text], {
		t.tag(`table`, {
			t.tag(`tr`, {
				t.tag(`td`, { 
					t.put(`Job:`);
				});
				t.tag(`td`, {
					t.putJobID(result.jobID);
				});
			});
			t.tag(`tr`, {
				t.tag(`td`, { 
					t.put(`Repository:`);
				});
				t.tag(`td`, {
					t.putRepoID(result.state.spec);
				});
			});
			t.tag(`tr`, {
				t.tag(`td`, { 
					t.put(`Commit:`);
				});
				t.tag(`td`, {
					t.putCommitID(result.state.spec);
				});
			});
			t.tag(`tr`, {
				t.tag(`td`, { 
					t.put(`Start time:`);
				});
				t.tag(`td`, {
					t.putDate!true(result.state.startTime);
				});
			});
			t.tag(`tr`, {
				t.tag(`td`, { 
					t.put(`Finish time:`);
				});
				t.tag(`td`, {
					t.putDate!true(result.state.finishTime);
				});
			});
			t.tag(`tr`, {
				t.tag(`td`, { 
					t.put(`Duration:`);
				});
				t.tag(`td`, {
					t.putDuration(result.state.startTime, result.state.finishTime);
				});
			});
			t.tag(`tr`, {
				t.tag(`td`, { 
					t.put(`Status:`);
				});
				t.tag(`td`, {
					t.putJobStatus!true(result.state);
				});
			});
		});
	});
}

void putRepoID(HTMLTerm t, JobSpec spec)
{
	t.tag(`div`, ["class" : "repository"], {
		t.tag(`div`, ["class" : "icon"], {});
		if (spec.repo)
		{
			assert(spec.repo.isRepoID);
			string[string] attrs;
			attrs["href"] = t.context.relPath(["repo"] ~ spec.repo.split("/") ~ [""]);
			if (spec.cloneURL)
				attrs["title"] = "Cloned from " ~ spec.cloneURL;
			t.tag(`a`, attrs, {
				t.put(spec.repo);
			});
		}
		else
			t.put("-");
	});
}

void putCommitID(HTMLTerm t, JobSpec spec)
{
	t.tag(`div`, ["class" : "commit"], {
		t.tag(`div`, ["class" : "icon"], {});
		if (spec.commit)
		{
			assert(spec.commit.isCommitID);
			// TODO: commit description
			t.tag(`a`, ["href" : t.context.relPath(["commit"] ~ spec.repo.split("/") ~ [spec.commit, ""])], {
				t.put(spec.commit);
			});
		}
		else
			t.put("-");
	});
}

void putJobID(HTMLTerm t, string jobID)
{
	t.tag(`div`, ["class" : "job"], {
		t.tag(`div`, ["class" : "icon"], {});
		if (jobID)
		{
			assert(jobID.isJobID);
			t.tag(`a`, ["href" : t.context.relPath("job", jobID, "")], {
				t.put(jobID);
			});
		}
		else
			t.put("-");
	});
}

void putJobStatus(bool full)(HTMLTerm t, JobState state)
{
	t.tag(`div`, ["class" : "status-" ~ state.status.text], {
		t.tag(`div`, ["class" : "icon"], {});
		string[string] attrs;
		static if (!full)
			if (state.statusText)
				attrs["title"] = state.statusText;
		t.tag(`span`, attrs, {
			t.put(t.fg(jobStatusColor(state.status)), state.status); // TODO: Link to bottom of log
			static if (full)
				if (state.statusText)
					t.put(" (", state.statusText, ")");
		});
	});
}

void putDate(bool full)(HTMLTerm t, StdTime stdTime)
{
	t.tag(`div`, ["class" : "date"], {
		t.tag(`div`, ["class" : "icon"], {});
		if (stdTime)
		{
			auto time = stdTime.SysTime;
			t.tag(`span`, ["title" : text(Clock.currTime - time, " ago")], {
				static if (full)
					t.put(time.formatTime!timeFormat);
				else
					t.put(time.formatTime!"Y-m-d H:i:s");
			});
		}
		else
			t.put('-');
	});
}

void putDuration(HTMLTerm t, StdTime startTime, StdTime finishTime)
{
	t.tag(`div`, ["class" : "duration"], {
		t.tag(`div`, ["class" : "icon"], {});
		if (finishTime)
		{
			auto duration = (finishTime - startTime).stdDur;
			t.tag(`span`, ["title" : text(duration)], {
				t.put(duration.DurationFmt);
			});
		}
		else
			t.put('-');
	});
}
