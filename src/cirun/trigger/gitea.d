/**
 * Gitea trigger.
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

module cirun.trigger.gitea;

import std.conv;
import std.exception;
import std.string;

import ae.net.http.common;
import ae.sys.data;
import ae.sys.net;
import ae.utils.json;

import cirun.common.config;
import cirun.trigger;

struct GiteaTriggerConfig
{
	string endpoint;
	string token;
	string context = "cirun";
}

void checkTriggerConfig(TriggerConfig.Type type)(in ref TriggerConfig config)
if (type == TriggerConfig.Type.giteaCommitStatus)
{
	enforce(config.gitea.endpoint, "Gitea trigger API endpoint not set");
	enforce(config.gitea.token, "Gitea trigger API token not set");
}

void runTrigger(TriggerConfig.Type type)(in ref TriggerConfig config, in ref TriggerEvent event)
if (type == TriggerConfig.Type.giteaCommitStatus)
{
	auto url = config.gitea.endpoint.chomp("/") ~ "/repos/" ~ event.job.spec.repo ~ "/statuses/" ~ event.job.spec.commit;
	auto req = new HttpRequest(url);
	req.headers["Authorization"] = "token " ~ config.gitea.token;
	req.method = "POST";
	req.headers["Content-Type"] = "application/json";

	static struct Body
	{
		string context, description, state, target_url;
	}
	Body triggerBody;
	triggerBody.context = config.gitea.context;
	triggerBody.description = "Job " ~ event.type.to!string;
	final switch (event.type)
	{
		case TriggerEvent.Type.queued   : triggerBody.state = "pending"; break;
		case TriggerEvent.Type.starting : triggerBody.state = "pending"; break;
		case TriggerEvent.Type.running  : triggerBody.state = "pending"; break;
		case TriggerEvent.Type.succeeded: triggerBody.state = "success"; break;
		case TriggerEvent.Type.failed   : triggerBody.state = "failure"; break;
		case TriggerEvent.Type.errored  : triggerBody.state = "error"; break;
		case TriggerEvent.Type.cancelled: triggerBody.state = "error"; break;
	}
	triggerBody.target_url = .config.externalUrlPrefix ~ "job/" ~ event.job.jobID;
	req.data = [Data(triggerBody.toJson)];

	auto res = net.httpRequest(req);
	enforce(res.status == HttpStatusCode.OK, "Failed to post gitea status: " ~ res.statusMessage);
}
