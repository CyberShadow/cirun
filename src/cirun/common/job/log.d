/**
 * Job log processing.
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

module cirun.common.job.log;

import std.range;
import std.string;

import ae.utils.appender;
import ae.utils.meta;
import ae.utils.time;

import cirun.common.state;

/// Preprocess a log range into a format better suitable for display,
/// i.e., one event per line.
void preprocessLog(bool reverse, R)(R entries, void delegate(ref JobLogEntry) sink)
{
	enum numStreams = enumLength!(JobLogEntry.Data.Stream); // 2
	FastAppender!char[numStreams] buffers;
	alias Timestamp = StdTime[2];
	Timestamp[numStreams] currentLineStart;

	static string dirCopy(in char[] bufLine) pure
	{
		static if (!reverse)
			return bufLine.idup;
		else
		{
			auto revLine = new char[bufLine.length];
			size_t p = 0;
			foreach_reverse (c; bufLine)
				revLine[p++] = c;
			return revLine;
		}
	}

	void flushStream(JobLogEntry.Data.Stream stream)
	{
		if (buffers[stream].length)
		{
			JobLogEntry e = {
				time : currentLineStart[stream][0],
				elapsed : currentLineStart[stream][1],
				data : JobLogEntry.Data(stream, dirCopy(buffers[stream].get))
			};
			sink(e);
			buffers[stream].clear();
		}
	}

	void flush()
	{
		if ((currentLineStart[JobLogEntry.Data.Stream.stdout][1] > currentLineStart[JobLogEntry.Data.Stream.stderr][1]) == reverse)
		{
			flushStream(JobLogEntry.Data.Stream.stdout);
			flushStream(JobLogEntry.Data.Stream.stderr);
		}
		else
		{
			flushStream(JobLogEntry.Data.Stream.stderr);
			flushStream(JobLogEntry.Data.Stream.stdout);
		}
	}

	foreach (ref entry; entries)
	{
		if (!entry.data.isNull)
		{
			auto text = entry.data.get.text;
			auto stream = entry.data.get.stream;
			Timestamp timestamp = [entry.time, entry.elapsed];

			// Note: this algorithm is suboptimal, as it iterates char-by-char, and always allocates.
			// A faster algorithm is possible (allocate only when a line crosses a log entry boundary),
			// but would be considerably more complicated.

			static if (reverse)
				auto r = text.representation.retro;
			else
				auto r = text.representation;
			foreach (c; r)
			{
				if (c == '\n')
				{
					static if (!reverse)
					{
						buffers[stream].put(c);
						flush();
					}
					else
					{
						flush();
						buffers[stream].put(c);
					}
				}
				else
				{
					static if (reverse)
						currentLineStart[stream] = timestamp;
					else
					{
						if (!buffers[stream].length)
							currentLineStart[stream] = timestamp;
					}
					buffers[stream].put(c);
				}
			}
		}
		else
		{
			flush();
			sink(entry);
		}
	}
	flush();
}

unittest
{
	if (false)
	{
		JobLogEntry[] log;
		preprocessLog!false(log, null);
		preprocessLog!true(log, null);
	}
}
