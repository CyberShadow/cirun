/**
 * Job status formatting.
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

module cirun.common.job.format;

import std.array;
import std.conv;
import std.exception;
import std.format;

import ae.utils.array;
import ae.utils.time : StdTime;

import cirun.ci.job;

/// See the documentation of the "format" switch for the "status"
/// action for a description of the format string syntax.
string formatJobResult(ref JobResult jobResult, string format)
{
	char next()
	{
		enforce(format.length, "Unexpected end of format string");
		return format.shift();
	}

	auto result = appender!string;

	void putTime(StdTime time)
	{
		auto c = next();
		switch (c)
		{
			case 's':
				result.formattedWrite!"%s"(time);
				break;
			default:
				throw new Exception("Unknown time format character: " ~ c);
		}
	}

	while (format.length)
	{
		auto c = next();
		if (c == '%')
		{
			c = next();
			switch (c)
			{
				case 'j':
					result ~= jobResult.jobID;
					break;
				case 'r':
					result ~= jobResult.state.spec.repo;
					break;
				case 'c':
					result ~= jobResult.state.spec.commit;
					break;
				case 's':
					result ~= jobResult.state.status.text;
					break;
				case 'S':
					result ~= jobResult.state.statusText;
					break;
				case 'b':
					putTime(jobResult.state.startTime);
					break;
				case 'e':
					putTime(jobResult.state.finishTime);
					break;
				case '%':
					result ~= '%';
					break;
				default:
					throw new Exception("Unknown job status format character: " ~ c);
			}
		}
		else
			result ~= c;
	}
	return result.data;
}
