/**
 * HTML fragments.
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

module cirun.web.html.bits;

import std.array;
import std.conv : text;
import std.datetime.systime : SysTime;

import ae.utils.time : StdTime, stdDur;
import ae.utils.time.format : formatTime;

import cirun.cli.term : DurationFmt, jobStatusColor, jobStatusText, timeFormat;
import cirun.common.ids;
import cirun.common.state;
import cirun.web.html.output;

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
			t.put(t.fg(jobStatusColor(state.status)), jobStatusText(state.status)); // TODO: Link to bottom of log
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
			t.tag(`span`, ["title" : text(t.startTime - time, " ago")], {
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
