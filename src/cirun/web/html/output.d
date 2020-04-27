/**
 * HTML output utility class.
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

module cirun.web.html.output;

import std.conv;

import ae.sys.term;
import ae.utils.appender;
import ae.utils.xml.entities;

class HTMLTerm : Term
{
	FastAppender!char buffer;

	static HTMLTerm getInstance()
	{
		static HTMLTerm instance;
		if (!instance)
			instance = new HTMLTerm();
		instance.buffer.clear();
		return instance;
	}

	void putHTML(in char[] s)
	{
		flush();
		buffer.put(s);
	}

	void tag(string tag, void delegate() inner)
	{
		flush();
		buffer.put(`<`, tag, `>`);
		inner();
		flush();
		buffer.put(`</`, tag, `>`);
	}

	void flush()
	{
		if (inSpan)
		{
			buffer.put(`</span>`);
			inSpan = false;
		}
	}

protected:
	override void putText(in char[] s)
	{
		buffer.putEncodedEntities(s);
	}

	override void setTextColor(Color c)
	{
		flush();
		if (c != Color.none)
		{
			buffer.put(`<span class="color-`, c.text, `">`);
			inSpan = true;
		}
	}

	override void setBackgroundColor(Color c) { assert(false); }
	override void setColor(Color fg, Color bg) { assert(false); }

private:
	bool inSpan;
}
