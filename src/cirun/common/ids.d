/**
 * Specification of string identifiers used by cirun.
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

module cirun.common.ids;

import std.algorithm.comparison : among;
import std.algorithm.searching : all;
import std.ascii;
import std.string;

import ae.utils.time.common;

bool isRepoID(string repo)
{
	auto parts = repo.split('/');
	return parts.length && parts.all!(part =>
		part.length &&
		part != "." &&
		part != ".." &&
		part.representation.all!((char c) =>
			isAlphaNum(c) || c.among('-', '_', '.')
		)
	);
}

bool isCommitID(string commit)
{
	return commit.length == 40 && commit.representation.all!(c => isDigit(c) || (c >= 'a' && c <= 'f'));
}

enum jobIDTimeFormat = "YmdHisu";
enum jobIDLength = timeFormatSize(jobIDTimeFormat);
static assert(jobIDLength == "20200101223344123456".length);

bool isJobID(string jobID)
{
	// Valid until year 9999
	return jobID.length == jobIDLength && jobID.representation.all!isDigit;
}
