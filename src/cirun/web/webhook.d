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

import std.conv;
import std.digest.hmac;
import std.digest.sha;
import std.exception;
import std.json;
import std.string;

import ae.net.http.common;
import ae.net.ietf.url;
import ae.sys.dataset;
import ae.utils.array;
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
			string event;
			if (webhookConfig.type == Config.Server.WebHook.Type.gogs)
				event = request.headers.get("X-Gogs-Event", null).enforce("No X-Gogs-Event header");
			else
				event = request.headers.get("X-Gitea-Event", null).enforce("No X-Gitea-Event header");
			switch (event)
			{
				case "push":
				{
					if (json["after"].str == "0000000000000000000000000000000000000000")
						return null; // ping
					JobSpec spec;
					spec.repo              = json["repository"]["full_name"].str;
					spec.cloneURL          = json["repository"]["clone_url"].str;
					spec.commit            = json["after"].str;
					spec.refName           = json["ref"].str;
					spec.commitMessage     = json["commits"][0]["message"].str;
					spec.commitAuthorName  = json["commits"][0]["author"]["name"].str;
					spec.commitAuthorEmail = json["commits"][0]["author"]["email"].str;
					spec.commitURL         = json["commits"][0]["url"].str;
					return [spec];
				}
				case "pull_request":
					switch (json["action"].str)
					{
						case "opened":
						case "synchronized":
						{
							JobSpec spec;
							spec.repo     = json["pull_request"]["base"]["repo"]["full_name"].str;
							spec.cloneURL = json["pull_request"]["head"]["repo"]["clone_url"].str;
							spec.commit   = json["pull_request"]["head"]["sha"].str;
							spec.refName  = "pr:" ~ json["pull_request"]["number"].integer.to!string;
							spec.refURL   = json["pull_request"]["html_url"].str;
							return [spec];
						}
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
				{
					JobSpec spec;
					spec.repo              = json["repository"]["full_name"].str;
					spec.cloneURL          = json["repository"]["clone_url"].str;
					spec.commit            = json["after"].str;
					spec.refName           = json["ref"].str;
					spec.commitMessage     = json["commits"][0]["message"].str;
					spec.commitAuthorName  = json["commits"][0]["author"]["name"].str;
					spec.commitAuthorEmail = json["commits"][0]["author"]["email"].str;
					spec.commitURL         = json["commits"][0]["url"].str;
					return [spec];
				}
				case "pull_request":
					switch (json["action"].str)
					{
						case "opened":
						case "synchronize":
							JobSpec spec;
							spec.repo     = json["pull_request"]["base"]["repo"]["full_name"].str;
							spec.cloneURL = json["pull_request"]["head"]["repo"]["clone_url"].str;
							spec.commit   = json["pull_request"]["head"]["sha"].str;
							spec.refName  = "pr:" ~ json["pull_request"]["number"].integer.to!string;
							spec.refURL   = json["pull_request"]["html_url"].str;
							return [spec];
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
				{
					JobSpec spec;
					spec.repo              = json["project"]["path_with_namespace"].str;
					spec.cloneURL          = json["project"]["url"].str;
					spec.commit            = json["after"].str;
					spec.refName           = json["ref"].str;
					spec.commitMessage     = json["commits"][0]["message"].str;
					spec.commitAuthorName  = json["commits"][0]["author"]["name"].str;
					spec.commitAuthorEmail = json["commits"][0]["author"]["email"].str;
					spec.commitURL         = json["commits"][0]["url"].str;
					return [spec];
				}
				case "Merge Request Hook":
					switch (json["object_attributes"]["action"].str)
					{
						case "open":
						case "update":
						{
							JobSpec spec;
							spec.repo              = json["object_attributes"]["target"]["path_with_namespace"].str;
							spec.cloneURL          = json["object_attributes"]["source"]["ssh_url"].str;
							spec.commit            = json["object_attributes"]["last_commit"]["id"].str;
							spec.refName           = "pr:" ~ json["object_attributes"]["iid"].integer.to!string;
							spec.refURL            = json["object_attributes"]["url"].str;
							spec.commitMessage     = json["object_attributes"]["last_commit"]["message"].str;
							spec.commitAuthorName  = json["object_attributes"]["last_commit"]["author"]["name"].str;
							spec.commitAuthorEmail = json["object_attributes"]["last_commit"]["author"]["email"].str;
							spec.commitURL         = json["object_attributes"]["last_commit"]["url"].str;
							return [spec];
						}
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
				{
					JobSpec spec;
					spec.repo     = json["repository"]["full_name"].str;
					// Note: Although BitBucket does provide a clone URL,
					// it requires a (possibly authenticated) API call.
					spec.cloneURL = json["repository"]["links"]["html"]["href"].str;
					spec.commit   = json["push"]["changes"][0]["new"]["target"]["hash"].str; // WTF!
					spec.refName  = "refs/heads/" ~ json["push"]["changes"][0]["new"]["name"].str;
					spec.refURL   = json["push"]["changes"][0]["new"]["links"]["html"]["href"].str;
					list(spec.commitAuthorName, spec.commitAuthorEmail) = json["push"]["changes"][0]["new"]["target"]["author"]["raw"].str.parseBitbucketAuthor;
					spec.commitURL = json["push"]["changes"][0]["new"]["target"]["links"]["html"]["href"].str;
					return [spec];
				}
				// TODO: Pull requests
				default:
					return null;
			}
		}
	}
}

private:

string[2] parseBitbucketAuthor(string author)
{
	auto p = author.lastIndexOf(" <");
	enforce(p >= 0 && author.endsWith(">"), "Bad author: " ~ author);
	return [author[0 .. p], author[p + 2 .. $ - 1]];
}
