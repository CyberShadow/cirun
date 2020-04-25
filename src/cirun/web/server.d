/**
 * HTTP server.
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

module cirun.web.server;

import std.algorithm.searching;
import std.exception;
import std.file;
import std.socket;

import ae.net.asockets;
import ae.net.http.responseex;
import ae.net.http.server;
import ae.net.shutdown;
import ae.sys.log;

import cirun.web.request;

version (SSL)
{
	import ae.net.ssl.openssl;
	mixin SSLUseLib;
}

import cirun.common.config;

void startServers()
{
	foreach (name, serverConfig; config.server)
		startServer(name, serverConfig);

	socketManager.loop();
}

private:

void startServer(string name, immutable Config.Server serverConfig)
{
	enforce(serverConfig.prefix.startsWith("/") &&serverConfig.prefix.endsWith("/"),
		"Server prefix should start and end with /");

	HttpServer server;
	if (serverConfig.ssl !is Config.Server.SSL.init)
	{
		version (SSL)
		{
			auto https = new HttpsServer();
			https.ctx.setCertificate(sslCert);
			https.ctx.setPrivateKey(sslKey);
			server = https;
		}
		else
			throw new Exception("This cirun executable was built without SSL support. Cannot use SSL, sorry!");
	}
	else
		server = new HttpServer();

	server.log = consoleLogger("Server-" ~ name);
	server.handleRequest =
		(HttpRequest request, HttpServerConnection conn)
		{
			handleRequest(
				request, serverConfig,
				(HttpResponse r) => conn.sendResponse(r),
				server.log);
		};

	string socketPath;
	if (serverConfig.listen.socketPath)
	{
		enforce(!serverConfig.listen.addr && !serverConfig.listen.port,
			"Both listen addr/port and socketPath are specified");
		static if (is(UnixAddress))
		{
			socketPath = serverConfig.listen.socketPath;
			// Work around "path too long" errors with long $PWD
			{
				import std.path : relativePath;
				auto relPath = relativePath(socketPath);
				if (relPath.length < socketPath.length)
					socketPath = relPath;
			}
			socketPath.remove().collectException();

			AddressInfo ai;
			ai.family = AddressFamily.UNIX;
			ai.type = SocketType.STREAM;
			ai.address = new UnixAddress(socketPath);
			server.listen([ai]);
		}
		else
			throw new Exception("UNIX sockets are not available on this platform");
	}
	else
		server.listen(serverConfig.listen.port, serverConfig.listen.addr);

	addShutdownHandler({
		server.close();
		if (socketPath)
			socketPath.remove();
	});
}
