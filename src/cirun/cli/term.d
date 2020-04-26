/**
 * Pretty-printing for CLI.
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

module cirun.cli.term;

import core.time;

import std.algorithm.comparison;
import std.algorithm.iteration;
import std.algorithm.sorting;
import std.array;
import std.conv;
import std.datetime.systime;
import std.format;
import std.process;
import std.string;
import std.traits;

import ae.sys.term;
import ae.utils.exception;
import ae.utils.time : StdTime;
import ae.utils.time.format;

import cirun.common.state;
import cirun.ci.job;
import cirun.common.job.log;

enum timeFormat = "Y-m-d H:i:s.u";

void printGlobalStatus()
{
	auto results = getGlobalState().updateJobs();
	auto t = term;
	t.put("  Jobs: ");
	foreach (g; results.map!(result => result.state.status).array.sort.group)
		t.put(t.fg(jobStatusColor(g[0])), g[1], t.none, " ", g[0], ", ");
	t.put(results.length, " total\n");
	foreach (result; results)
		printJobSummary(result);
}

void printGlobalHistory()
{
	foreach (ref job; getGlobalHistoryReader.reverseIter)
		if (job is Job.parseErrorValue)
			printJobSummary(JobResult(null, JobState(JobSpec.init, JobStatus.corrupted, "(corrupted global history entry)")));
		else
			printJobSummary(getJobResult(job.jobID));
}

auto formatted(string fmt, T...)(auto ref T values)
{
	static struct Formatted
	{
		T values;
		void toString(void delegate(const(char)[]) sink) const
		{
			sink.formattedWrite!fmt(values);
		}
	}
	return Formatted(values);
}

enum maxStatusLength = [EnumMembers!(JobStatus)].map!(status => jobStatusText(status).length).reduce!max;

void printJobSummary(JobResult result)
{
	auto t = term;
	t.put(
		t.fg(jobStatusColor(result.state.status)),
	//	"• ",
		formatted!"%*s"(maxStatusLength, jobStatusText(result.state.status)),
		t.none,
	);
	if (result.jobID)
	{
		t.put(
			" ",
			result.jobID,
		);
		if (result.state.spec.repo || result.state.spec.commit)
			t.put(
				" (",
				formatted!"%-20s"(result.state.spec.repo),
				" @ ",
				result.state.spec.commit,
				")",
			);
	}
	else
	if (result.state.statusText)
		t.put(" ", t.brightRed, result.state.statusText, t.none);
	t.put("\n");
}

Term.Color jobStatusColor(JobStatus status)
{
	final switch (status)
	{
		case JobStatus.queued:
		case JobStatus.starting:
		case JobStatus.running:
			return Term.Color.brightYellow;
		case JobStatus.success:
			return Term.Color.brightGreen;
		case JobStatus.failure:
		case JobStatus.errored:
		case JobStatus.corrupted:
			return Term.Color.brightRed;
		case JobStatus.cancelled:
		case JobStatus.none:
			return Term.Color.darkGray;
	}
}

string jobStatusText(JobStatus status)
{
	switch (status)
	{
		case JobStatus.none:
			return "(no data)";
		default:
			return status.text;
	}
}

void printJobResult(ref JobResult result)
{
	auto t = term;
	if (result.jobID)
		t.put("         Job: ", result.jobID, "\n");
	if (result.state.spec.repo)
		t.put("  Repository: ", result.state.spec.repo, "\n");
	if (result.state.spec.commit)
		t.put("      Commit: ", result.state.spec.commit, "\n");
	if (result.state.startTime)
		t.put("  Start time: ", result.state.startTime.SysTime.formatTime!timeFormat, "\n");
	if (result.state.finishTime)
		t.put(" Finish time: ", result.state.finishTime.SysTime.formatTime!timeFormat,
			" (ran for ", result.state.finishTime.SysTime - result.state.startTime.SysTime, ")",
			"\n");
	t.put("      Status: ");
	t.put(t.fg(jobStatusColor(result.state.status)));
	t.put(jobStatusText(result.state.status));
	if (result.state.statusText)
		t.put(" (", result.state.statusText, ")");
	t.put(t.none, "\n");

	if (result.jobID)
	{
		auto log = getJobLogReader(result.jobID);

		enum numLines = 10;
		JobLogEntry[numLines] lines;
		size_t pos = numLines;
		class Stop : Throwable { this() { super(null); } }
		static const stop = new Stop;
		try
			log.reverseIter.preprocessLog!true((ref entry) {
				if (pos == 0)
					throw stop;
				else
					lines[--pos] = entry;
			});
		catch (Stop)
		{}

		t.put('\n');

		JobLogPrinter p;
		foreach (ref entry; lines[pos .. $])
			p.printEntry(entry);
	}
}

void printJobLog(string jobID)
{
	JobLogPrinter p;
	getJobLogReader(jobID).iter.preprocessLog!false(&p.printEntry);
}

struct DurationFmt
{
	Duration d;

	void toString(void delegate(const(char)[]) sink) const
	{
		long hours, minutes, seconds, msecs;
		d.split!("hours", "minutes", "seconds", "msecs")(hours, minutes, seconds, msecs);
		if (hours)
			sink.formattedWrite!"%d:"(hours);
		sink.formattedWrite!"%02d:%02d.%03d"(minutes, seconds, msecs);
	}
}

size_t textLength(T)(auto ref T value)
{
	size_t length;
	value.toString(
		(const(char)[] str)
		{
			length += str.length;
		});
	return length;
}

struct JobLogPrinter
{
	StdTime lastElapsed = StdTime.max;
	size_t lastTimeLength;

	void printEntry(ref JobLogEntry e)
	{
		auto t = term;

		if (e is JobLogEntry.parseErrorValue)
		{
			t.put(formatted!"%*s"(lastTimeLength, ""), t.brightRed, "(corrupted log entry)", t.none, "\n");
			return;
		}

		auto fmtTime = formatted!"[%s +%s] "(e.time.SysTime.formatTime!"H:i:s", e.elapsed.hnsecs.DurationFmt);
		auto timeLength = textLength(fmtTime);
		if (e.elapsed == lastElapsed)
			t.put(formatted!"%*s"(timeLength, ""));
		else
			t.put(t.darkGray, fmtTime);
		lastElapsed = e.elapsed;
		lastTimeLength = timeLength;

		if (!e.jobStart.isNull)
		{
			t.put(t.cyan, "Job started.\n", formatted!"%*s"(timeLength, ""), "Environment:\n");
			foreach (name, value; e.jobStart.get.environment)
				t.put(formatted!"%*s"(timeLength + 2, ""), name, "=", value, "\n");
			t.put(formatted!"%*s"(timeLength, ""), "Working directory: ", e.jobStart.get.currentDirectory);
		}
		else
		if (!e.jobFinish.isNull)
		{
			t.put(t.cyan, "Job finished with status ", t.fg(jobStatusColor(e.jobFinish.get.status)), jobStatusText(e.jobFinish.get.status));
			if (e.jobFinish.get.statusText)
				t.put(" (", e.jobFinish.get.statusText, ")");
		}
		else
		if (!e.processStart.isNull)
			t.put(t.cyan, "Process started: ", escapeShellCommand(e.processStart.get.commandLine));
		else
		if (!e.processFinish.isNull)
			t.put(e.processFinish.get.exitCode == 0 ? t.cyan : t.red, "Process finished with exit code ", e.processFinish.get.exitCode);
		else
		if (!e.data.isNull)
			t.put(e.data.get.stream == JobLogEntry.Data.Stream.stderr ? t.yellow : t.none, e.data.get.text.chomp);

		t.put(t.none, '\n');
	}
}
