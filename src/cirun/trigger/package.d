/**
 * Top-level trigger module.
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

module cirun.trigger;

import std.stdio : stderr;
import std.traits : EnumMembers;

import ae.utils.array;

import cirun.common.config;
import cirun.common.state;

struct TriggerEvent
{
	Job job;

	enum Type
	{
		queued,
		starting,
		running,
		succeeded,
		failed,
		errored,
		cancelled,
	}

	Type type;
}

struct TriggerConfig
{
	TriggerEvent.Type[] events = [
		TriggerEvent.Type.failed,
		TriggerEvent.Type.errored,
	];

	enum Type
	{
		none,
	}
	Type type;
}

void checkTriggersConfig()
{
	foreach (name, ref triggerConfig; config.trigger)
	typeSwitch:
		final switch (triggerConfig.type)
		{
			case TriggerConfig.Type.none:
				throw new Exception("Trigger type not configured!");
		}
}

void runTriggers(TriggerEvent event)
{
	foreach (name, ref triggerConfig; config.trigger)
		if (triggerConfig.events.contains(event.type))
			try
			{
			typeSwitch:
				final switch (triggerConfig.type)
				{
					case TriggerConfig.Type.none:
						assert(false);
				}
			}
			catch (Exception e)
				stderr.writeln("Error while running trigger " ~ name ~ ":\n", e);
}
