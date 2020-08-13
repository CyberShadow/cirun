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
 *   Vladimir Panteleev <vladimir@cy.md>
 */

module cirun.web.html.bits;

import std.algorithm.searching;
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
			auto attrs = ["href" : t.context.relPath(["commit"] ~ spec.repo.split("/") ~ [spec.commit, ""])];
			if (spec.commitMessage)
			{
				auto commitMessage = spec.commitMessage;
				if (commitMessage.length > 256)
					commitMessage = commitMessage[0 .. 250] ~ "\&hellip;"; // ";
				attrs["title"] = commitMessage;
			}
			t.tag(`a`, attrs, {
				t.put(spec.commit);
			});
			if (spec.commitURL)
			{
				t.put("\&nbsp;"); // ";
				t.putExternalLink(spec.commitURL);
			}
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
	t.tag(`div`, ["class" : "status status-" ~ state.status.text], {
		t.tag(`div`, ["class" : "icon"], {});
		string[string] attrs;
		static if (!full)
			if (state.statusText)
				attrs["title"] = state.statusText;
		t.tag(`span`, attrs, {
			t.put(jobStatusText(state.status)); // TODO: Link to bottom of log
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

void putRef(HTMLTerm t, string refName)
{
	auto icon =
		refName.startsWith("pr:") ? "pull-request" :
		refName.startsWith("refs/tags/") ? "tag" :
		"branch";
	t.tag(`div`, ["class" : icon], {
		t.tag(`div`, ["class" : "icon"], {});
		if (refName.skipOver("pr:"))
			t.put("#", refName);
		else
		if (refName.skipOver("refs/tags/") || refName.skipOver("refs/heads/") || refName !is null)
			t.put(refName);
		else
			t.put('-');
	});
}

void putAuthor(HTMLTerm t, string name, string email)
{
	t.tag(`div`, ["class" : "author"], {
		t.tag(`div`, ["class" : "icon"], {});
		if (name)
			t.put(name);
		else
		if (email)
			t.put(email);
		else
			t.put('-');
	});
}

void putExternalLink(HTMLTerm t, string url)
{
	t.tag(`a`, ["class" : "external-link", "href" : url], {
		t.tag(`div`, ["class" : "icon"], {});
	});
}
