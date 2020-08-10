/**
 * HTTP webhook handler.
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

module cirun.web.webhook;

import std.digest.hmac;
import std.digest.sha;
import std.exception;
import std.json;

import ae.net.http.common;
import ae.net.ietf.url;
import ae.sys.dataset;
import ae.utils.text;

import cirun.common.config;
import cirun.common.state;
import cirun.web.common;

JobSpec[] parseWebhook(in ref Config.Server.WebHook webhookConfig, HttpRequest request)
{
	string getBody()
	{
		(request.method == "POST").httpEnforce(HttpStatusCode.MethodNotAllowed);
		return cast(string)request.data.joinToHeap();
	}

	JSONValue getJSON(string resBody)
	{
		// GitHub, Gogs and Gitea allow configuring delivery as either
		// application/json or application/x-www-form-urlencoded.
		string json;
		switch (request.headers.get("Content-Type", null).httpEnforce(HttpStatusCode.BadRequest, "No Content-Type"))
		{
			case "application/json":
				json = resBody;
				break;
			case "application/x-www-form-urlencoded":
				auto parameters = decodeUrlParameters(resBody);
				json = parameters.get("payload", null).enforce("No payload in application/x-www-form-urlencoded");
				break;
			default:
				false.httpEnforce(HttpStatusCode.UnsupportedMediaType, "Unknown Content-Type: " ~ request.headers["Content-Type"]);
		}
		return parseJSON(json);
	}

	final switch (webhookConfig.type)
	{
		case Config.Server.WebHook.Type.none:
			throw new Exception("WebHook type not configured");

		case Config.Server.WebHook.Type.gogs:
		case Config.Server.WebHook.Type.gitea:
		{
			auto json = getJSON(getBody());
			enforce(json["secret"].str == webhookConfig.secret, "Webhook secret mismatch");
			switch (request.headers.get("X-Gogs-Event", null).enforce("No X-Gogs-Event header"))
			{
				case "push":
					if (json["after"].str == "0000000000000000000000000000000000000000")
						return null; // ping
					return [JobSpec(
						json["repository"]["full_name"].str,
						json["repository"]["clone_url"].str,
						json["after"].str,
					)];
				case "pull_request":
					switch (json["action"].str)
					{
						case "opened":
						case "synchronized":
							return [JobSpec(
								json["pull_request"]["base"]["repo"]["full_name"].str,
								json["pull_request"]["head"]["repo"]["clone_url"].str,
								json["pull_request"]["head"]["sha"].str,
							)];
						default:
							return null;
					}
				default:
					return null;
			}
		}

		case Config.Server.WebHook.Type.github:
		{
			auto resBody = getBody();
			if (webhookConfig.secret)
			{
				auto suppliedSignature = request.headers.get("X-Hub-Signature", null)
					.enforce("Secret configured, but no X-Hub-Signature header found");
				auto expectedSignature = "sha1=" ~ hmac!SHA1(cast(ubyte[])resBody, cast(ubyte[])webhookConfig.secret).toLowerHex;
				enforce(suppliedSignature == expectedSignature, "Secret signature mismatch");
			}
			else
				enforce("X-Hub-Signature" !in request.headers, "X-Hub-Signature header present but no webhook secret is configured");

			auto json = getJSON(resBody);
			switch (request.headers.get("X-GitHub-Event", null).enforce("No X-GitHub-Event header"))
			{
				case "push":
					return [JobSpec(
						json["repository"]["full_name"].str,
						json["repository"]["clone_url"].str,
						json["after"].str,
					)];
				case "pull_request":
					switch (json["action"].str)
					{
						case "opened":
						case "synchronize":
							return [JobSpec(
								json["pull_request"]["base"]["repo"]["full_name"].str,
								json["pull_request"]["head"]["repo"]["clone_url"].str,
								json["pull_request"]["head"]["sha"].str,
							)];
						default:
							return null;
					}
				default:
					return null;
			}
		}

		case Config.Server.WebHook.Type.gitlab:
		{
			enforce(request.headers.get("X-Gitlab-Token", null) == webhookConfig.secret, "Webhook secret mismatch");

			auto json = getJSON(getBody());
			switch (request.headers.get("X-Gitlab-Event", null).enforce("No X-Gitlab-Event header"))
			{
				case "Push Hook":
					return [JobSpec(
						json["project"]["path_with_namespace"].str,
						json["project"]["url"].str,
						json["after"].str,
					)];
				case "Merge Request Hook":
					switch (json["object_attributes"]["action"].str)
					{
						case "open":
						case "update":
							return [JobSpec(
								json["object_attributes"]["target"]["path_with_namespace"].str,
								json["object_attributes"]["source"]["ssh_url"].str,
								json["object_attributes"]["last_commit"]["id"].str,
							)];
						default:
							return null;
					}
				default:
					return null;
			}
		}

		case Config.Server.WebHook.Type.bitbucket:
		{
			enforce(webhookConfig.secret is null, "This hook type does not support configuring a secret");

			auto json = getJSON(getBody());
			switch (request.headers.get("X-Event-Key", null).enforce("No X-Event-Key header"))
			{
				case "repo:push":
					return [JobSpec(
						json["repository"]["full_name"].str,
						// Note: Although BitBucket does provide a clone URL,
						// it requires a (possibly authenticated) API call.
						json["repository"]["links"]["html"]["href"].str,
						json["push"]["changes"][0]["new"]["target"]["hash"].str, // WTF!
					)];
				// TODO: Pull requests
				default:
					return null;
			}
		}
	}
}
