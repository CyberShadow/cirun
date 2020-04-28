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
		t.putJobSummary(result);

	t.tag(`h2`, { t.put("History"); });

	enum numHistoryEntries = 10;
	t.tag(`p`, { t.put("Last ", numHistoryEntries, " jobs:"); });
	t.printGlobalHistory(getGlobalHistoryReader.reverseIter.take(numHistoryEntries));

	t.finish("Status");
}

void printGlobalHistory(R)(HTMLTerm t, R jobs)
{
	foreach (ref job; jobs)
		if (job is Job.parseErrorValue)
			t.putJobSummary(JobResult(null, JobState(JobSpec.init, JobStatus.corrupted, "(corrupted global history entry)")));
		else
			t.putJobSummary(getJobResult(job.jobID));
}

void putJobSummary(HTMLTerm t, JobResult result)
{
	t.tag(`div`, ["class" : "job-box status-" ~ result.state.status.text], {
		t.tag(`div`, {
			t.tag(`div`, ["class" : "repository"], {
				t.tag(`div`, ["class" : "icon"], {});
				if (result.state.spec.repo)
					t.put(result.state.spec.repo); // TODO: Link?
				else
					t.put("-");
			});
			t.tag(`div`, ["class" : "commit"], {
				t.tag(`div`, ["class" : "icon"], {});
				if (result.state.spec.commit)
					t.put(result.state.spec.commit); // TODO: Link?
				else
					t.put("-");
			});
		});

		t.tag(`div`, {
			t.tag(`div`, ["class" : "job"], {
				t.tag(`div`, ["class" : "icon"], {});
				if (result.jobID)
					t.put(result.jobID); // TODO: Link
				else
					t.put("-");
			});
			t.tag(`div`, ["class" : "status-" ~ result.state.status.text], {
				t.tag(`div`, ["class" : "icon"], {});
				t.put(t.fg(jobStatusColor(result.state.status)), result.state.status); // TODO: Link to bottom of log
			});
		});

		t.tag(`div`, {
			t.tag(`div`, ["class" : "start-time"], {
				t.tag(`div`, ["class" : "icon"], {});
				if (result.state.startTime)
					t.put(result.state.startTime.SysTime.formatTime!"Y-m-d H:i:s");
				else
					t.put('-');
			});
			t.tag(`div`, ["class" : "duration"], {
				t.tag(`div`, ["class" : "icon"], {});
				if (result.state.finishTime)
					t.put((result.state.finishTime - result.state.startTime).stdDur.DurationFmt);
				else
					t.put('-');
			});
		});
	});
}
