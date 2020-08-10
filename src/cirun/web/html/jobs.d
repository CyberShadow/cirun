/**
 * Job listings and details.
 *
 * License:
 *   This Source Code Form is subject to the terms of
 *   the Mozilla Public License, v. 2.0. If a copy of
 *   the MPL was not distributed with this file, You
 *   can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * Authors:
 *   Vladimir Panteleev <vladimir@cy.md>
 */

module cirun.web.html.jobs;

import std.conv : text;
import std.range;

import ae.net.http.common : HttpStatusCode;

import cirun.ci.job;
import cirun.cli.term : JobLogPrinter;
import cirun.common.job.log;
import cirun.common.state;
import cirun.web.common;
import cirun.web.html.bits;
import cirun.web.html.output;

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

void putJobLog(R)(HTMLTerm t, R iter)
{
	t.tag(`h2`, { t.put("Log"); });

	t.tag(`pre`, ["class" : "job-log"], {
		auto p = JobLogPrinter(t);
		iter.preprocessLog!false(&p.printEntry);
	});
}
