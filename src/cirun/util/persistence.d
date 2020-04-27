/**
 * Utility code for on-disk persistence.
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

module cirun.util.persistence;

import std.algorithm.iteration;
import std.file;
import std.mmfile;
import std.range;
import std.stdio;
import std.string;
import std.typecons;

import ae.sys.datamm;
import ae.sys.file;
import ae.utils.json;

/// Represents an open file containing a JSON-encoded representation
/// of T, intended to be shared between concurrent cirun processes.
/// The file remains open and exclusively locked for the lifetime of
/// this object's instance; therefore, this object should not exist
/// for long periods of time, but note that its contents may change
/// between reopens.
alias Persistent(T) = RefCounted!(PersistentImpl!T);
struct PersistentImpl(T) /// ditto
{
	T value;

	this(string fileName)
	{
		this.fileName = fileName;

		lockFile.open(fileName ~ ".lock", "ab");
		lockFile.lock();

		if (fileName.exists && fileName.getSize > 0)
		{
			auto data = mapFile(fileName, MmMode.read);
			auto json = cast(string)data.contents;
			value = json.jsonParse!T;
		}
		origValue = value;
		assert(origValue == value);
	}

	@disable this(this);

	~this()
	{
		if (value != origValue)
			save();
	}

	void edit(scope void delegate(ref T value) dg)
	{
		dg(value);
	}

private:
	string fileName;
	File lockFile;

	T origValue;

	void saveTo(string target)
	{
		auto f = File(target, "wb");
		CustomJsonSerializer!(PrettyJsonWriter!FileWriter) serializer;
		serializer.writer.output = FileWriter(f);
		serializer.put(value);
	}

	void save()
	{
		atomicDg(&saveTo, fileName);
		origValue = value;
	}
}

unittest
{
	Persistent!string test; // test instantiation
}

/// Represents an append-only log or history file.
/// Entries are stored in LDJSON (line-delimited JSON).
struct LogWriter(T)
{
	private File f;

	this(string fileName)
	{
		f = openFile(fileName, "ab");
		f.lock();
		f.write('\n'); // Start a new line in case the previous record was incompletely written
	}

	void put()(auto ref T value)
	{
		{
			CustomJsonSerializer!(JsonWriter!FileWriter) serializer;
			serializer.writer.output = FileWriter(f);
			serializer.put(value);
			serializer.writer.output.put("\n");
		}
		f.flush();
	}

	bool isOpen() { return f.isOpen; }
}

unittest
{
	if (false) // test instantiation
	{
		LogWriter!string test;
		test.put("test");
	}
}

/// Reads files created by LogWriter.
struct LogReader(T)
{
	MmFile f;
	string data;

	this(string fileName)
	{
		// Can't map a zero-length file
		if (fileName.exists && getSize(fileName) > 0)
		{
			// Even though we are never going to write to the file, open
			// it in Mode.readWrite, so that std.mmfile opens it with
			// FILE_SHARE_READ | FILE_SHARE_WRITE on Windows (thus
			// allowing it to be appended to by a writer asynchronously).
			f = new MmFile(fileName, MmFile.Mode.readWrite, 0, null);
			data = cast(string)f[];
		}
	}

	static T parseRecord(string s)
	{
		try
			return jsonParse!T(s);
		catch (Exception e)
			return T.parseErrorValue;
	}

	auto iter()
	{
		return data
			.splitter('\n')
			.filter!(l => l.length)
			.map!parseRecord
		;
	}

	auto reverseIter()
	{
		return data
			.representation
			.retro
			.splitter('\n')
			.filter!(l => l.length)
			.map!retro
			.map!(bytes => cast(string)bytes)
			.map!parseRecord
		;
	}
}

unittest
{
	if (false) // test instantiation
	{
		struct S
		{
			enum S parseErrorValue = S(null);
			string s;
		}
		LogReader!S test;
	}
}

private struct FileWriter
{
	typeof(File.init.lockingBinaryWriter()) writer;
	this(File f) { writer = f.lockingBinaryWriter; }
	void put(in char[] s)
	{
		writer.put(s);
	}
}
