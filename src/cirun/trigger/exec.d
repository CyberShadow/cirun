/**
 * User-defined command execution trigger.
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

module cirun.trigger.exec;

import std.conv;
import std.exception;
import std.process;

import cirun.common.config;
import cirun.trigger;

struct ExecTriggerConfig
{
	string[] command;
}

void checkTriggerConfig(TriggerConfig.Type type)(in ref TriggerConfig config)
if (type == TriggerConfig.Type.exec)
{
	enforce(config.exec.command.length, "No exec command is specified");
}

void runTrigger(TriggerConfig.Type type)(in ref TriggerConfig config, in ref TriggerEvent event)
if (type == TriggerConfig.Type.exec)
{
	string[string] env;
	env["CIRUN_EVENT"] = event.type.to!string;
	env["CIRUN_REPO"] = event.job.spec.repo;
	env["CIRUN_COMMIT"] = event.job.spec.commit;
	env["CIRUN_JOB"] = event.job.jobID;
	enforce(spawnProcess(config.exec.command, env).wait() == 0, "Trigger command failed");
}
