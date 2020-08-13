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
 *   Vladimir Panteleev <vladimir@cy.md>
 */

module cirun.web.server;

debug version(unittest) version = SSL;

import std.algorithm.comparison;
import std.algorithm.searching;
import std.array;
import std.conv;
import std.exception;
import std.file;
import std.format;
import std.process : environment;
import std.socket;
import std.stdio : stderr;

import ae.net.asockets;
import ae.net.http.cgi.common;
import ae.net.http.cgi.script;
import ae.net.http.fastcgi.app;
import ae.net.http.responseex;
import ae.net.http.scgi.app;
import ae.net.http.server;
import ae.net.shutdown;
import ae.sys.log;
import ae.utils.array;

import cirun.web.request;

version (SSL)
{
	import ae.net.ssl;
	import ae.net.ssl.openssl;
	mixin SSLUseLib;
}

import cirun.common.config;

void startServer(string serverName)
{
	auto pserverConfig = serverName in config.server;
	pserverConfig.enforce(
		format!"Did not find a section named [server.%s] in %s."
		(serverName, configFileName));
	startServer(serverName, *pserverConfig, true);
	socketManager.loop();
}

void startServers()
{
	enforce(config.server.length, "No servers are configured.");

	foreach (name, ref serverConfig; config.server)
		startServer(name, serverConfig, false);

	enforce(socketManager.size(), "No servers to start!");
	socketManager.loop();
}

bool runImplicitServer()
{
	if (inCGI())
	{
		runImplicitServer(
			Config.Server.Transport.stdin,
			Config.Server.Protocol.cgi,
			"cgi",
			"CGI",
			"a CGI script");
		return true;
	}

	if (inFastCGI())
	{
		runImplicitServer(
			Config.Server.Transport.accept,
			Config.Server.Protocol.fastcgi,
			"fastcgi",
			"FastCGI",
			"a FastCGI application");
		return true;
	}

	return false;
}

private:

void runImplicitServer(
	Config.Server.Transport transport,
	Config.Server.Protocol protocol,
	string serverName,
	string protocolText,
	string kindText,
)
{
	auto pserverConfig = serverName in config.server;
	enum errorFmt =
		"cirun was invoked as %3$s, but no \"%1$s\" server is configured.\n\n" ~
		"Please add a section named [server.%1$s] to %2$s.";
	enforce(pserverConfig, format!errorFmt(serverName, configFileName, kindText));
	enforce(pserverConfig.transport == transport,
		format!"The transport must be set to %s in [server.%s] for implicit %s requests."
		(transport, serverName, protocolText));
	enforce(pserverConfig.protocol == protocol,
		format!"The protocol must be set to %s in [server.%s] for implicit %s requests."
		(protocol, serverName, protocolText));

	startServer(serverName, *pserverConfig, true);
	socketManager.loop();
}


void startServer(string name, in ref Config.Server serverConfig, bool exclusive)
{
	scope(failure) stderr.writefln("Error with server %s:", name);

	auto isSomeCGI = serverConfig.protocol.among(
		Config.Server.Protocol.cgi,
		Config.Server.Protocol.scgi,
		Config.Server.Protocol.fastcgi);

	// Check options
	if (serverConfig.listen.addr)
		enforce(serverConfig.transport == Config.Server.Transport.inet,
			"listen.addr should only be set with transport = inet");
	if (serverConfig.listen.port)
		enforce(serverConfig.transport == Config.Server.Transport.inet,
			"listen.port should only be set with transport = inet");
	if (serverConfig.listen.socketPath)
		enforce(serverConfig.transport == Config.Server.Transport.unix,
			"listen.socketPath should only be set with transport = unix");
	if (serverConfig.protocol == Config.Server.Protocol.cgi)
		enforce(serverConfig.transport == Config.Server.Transport.stdin,
			"CGI can only be used with transport = stdin");
	if (serverConfig.ssl.cert || serverConfig.ssl.key)
		enforce(serverConfig.protocol == Config.Server.Protocol.http,
			"SSL can only be used with protocol = http");
	if (!serverConfig.nph.isNull)
		enforce(isSomeCGI,
			"Setting NPH only makes sense with protocol = cgi, scgi, or fastcgi");
	enforce(serverConfig.prefix.startsWith("/") && serverConfig.prefix.endsWith("/"),
		"Server prefix should start and end with /");

	if (!exclusive && serverConfig.transport.among(
			Config.Server.Transport.stdin,
			Config.Server.Transport.accept))
	{
		stderr.writefln("Skipping exclusive server %1$s. (Run as \"server %1$s\" to start this server.)", name);
		return;
	}

	version (SSL) SSLContext ctx;
	if (serverConfig.ssl !is Config.Server.SSL.init)
	{
		version (SSL)
		{
			ctx = ssl.createContext(SSLContext.Kind.server);
			ctx.setCertificate(serverConfig.ssl.cert);
			ctx.setPrivateKey(serverConfig.ssl.key);
		}
		else
			throw new Exception("This cirun executable was built without SSL support. Cannot use SSL, sorry!");
	}

	// Place on heap to extend lifetime past scope,
	// even though this function creates a closure
	Logger* log = {
		Logger log;
		auto logName = "Server-" ~ name;
		switch (serverConfig.logDir)
		{
			case "/dev/stderr":
				log = consoleLogger(logName);
				break;
			case "/dev/null":
				log = nullLogger();
				break;
			default:
				log = fileLogger(logDir ~ "/" ~ logName);
				break;
		}
		return [log].ptr;
	}();

	TcpServer server;
	string protocol = join(
		(serverConfig.transport == Config.Server.Transport.inet ? [] : [serverConfig.transport.text]) ~
		(
			(serverConfig.protocol == Config.Server.Protocol.http && serverConfig.ssl !is Config.Server.SSL.init)
			? ["https"]
			: (
				[serverConfig.protocol.text] ~
				(serverConfig.ssl is Config.Server.SSL.init ? [] : ["tls"])
			)
		),
		"+");

	bool nph;
	if (isSomeCGI)
		nph = serverConfig.nph.isNull ? isNPH() : serverConfig.nph.get;

	string[] serverAddrs;
	if (serverConfig.protocol == Config.Server.Protocol.fastcgi)
		serverAddrs = environment.get("FCGI_WEB_SERVER_ADDRS", null).split(",");

	void handleConnection(IConnection c, string localAddressStr, string remoteAddressStr)
	{
		version (SSL) if (ctx)
			c = ssl.createAdapter(ctx, c);

		void handleRequest(HttpRequest request, void delegate(HttpResponse) handleResponse)
		{
			void logAndHandleResponse(HttpResponse response)
			{
				log.log([
					"", // align IP to tab
					request ? request.remoteHosts(remoteAddressStr).get(0, remoteAddressStr) : remoteAddressStr,
					response ? text(cast(ushort)response.status) : "-",
					request ? format("%9.2f ms", request.age.total!"usecs" / 1000f) : "-",
					request ? request.method : "-",
					request ? protocol ~ "://" ~ localAddressStr ~ request.resource : "-",
					response ? response.headers.get("Content-Type", "-") : "-",
					request ? request.headers.get("Referer", "-") : "-",
					request ? request.headers.get("User-Agent", "-") : "-",
				].join("\t"));

				handleResponse(response);
			}

			.handleRequest(request, serverConfig, &logAndHandleResponse, *log);
		}

		final switch (serverConfig.protocol)
		{
			case Config.Server.Protocol.cgi:
			{
				auto cgiRequest = readCGIRequest();
				auto request = new CGIHttpRequest(cgiRequest);
				bool responseWritten;
				void handleResponse(HttpResponse response)
				{
					if (nph)
						writeNPHResponse(response);
					else
						writeCGIResponse(response);
					responseWritten = true;
				}

				handleRequest(request, &handleResponse);
				assert(responseWritten);
				c.disconnect();
				break;
			}
			case Config.Server.Protocol.scgi:
			{
				auto conn = new SCGIConnection(c);
				conn.log = *log;
				conn.nph = nph;
				void handleSCGIRequest(ref CGIRequest cgiRequest)
				{
					auto request = new CGIHttpRequest(cgiRequest);
					handleRequest(request, &conn.sendResponse);
				}
				conn.handleRequest = &handleSCGIRequest;
				break;
			}
			case Config.Server.Protocol.fastcgi:
			{
				if (serverAddrs && !serverAddrs.canFind(remoteAddressStr))
				{
					log.log("Address not in FCGI_WEB_SERVER_ADDRS, rejecting");
					c.disconnect("Forbidden by FCGI_WEB_SERVER_ADDRS");
					return;
				}
				auto fconn = new FastCGIResponderConnection(c);
				fconn.log = *log;
				fconn.nph = nph;
				void handleCGIRequest(ref CGIRequest cgiRequest, void delegate(HttpResponse) handleResponse)
				{
					auto request = new CGIHttpRequest(cgiRequest);
					handleRequest(request, handleResponse);
				}
				fconn.handleRequest = &handleCGIRequest;
				break;
			}
			case Config.Server.Protocol.http:
			{
				alias connRemoteAddressStr = remoteAddressStr;
				alias handleServerRequest = handleRequest;

				final class HttpConnection : BaseHttpServerConnection
				{
				protected:
					this()
					{
						this.log = log;
						this.banner = "cirun (+https://github.com/CyberShadow/cirun)";
						this.handleRequest = &onRequest;

						super(c);
					}

					void onRequest(HttpRequest request)
					{
						handleServerRequest(request, &sendResponse);
					}

					override bool acceptMore() { return server ? server.isListening : false; }
					override string formatLocalAddress(HttpRequest r) { return protocol ~ "://" ~ localAddressStr; }
					override @property string remoteAddressStr() { return connRemoteAddressStr; }
				}
				new HttpConnection();
				break;
			}
		}
	}

	final switch (serverConfig.transport)
	{
		case Config.Server.Transport.stdin:
			static if (is(FileConnection))
			{
				import std.stdio : stdin, stdout;
				import core.sys.posix.unistd : dup;
				auto c = new Duplex(
					new FileConnection(stdin.fileno.dup),
					new FileConnection(stdout.fileno.dup),
				);
				handleConnection(c,
					environment.get("REMOTE_ADDR", "-"),
					environment.get("SERVER_NAME", "-"));
				return;
			}
			else
				throw new Exception("Sorry, transport = stdin is not supported on this platform!");
		case Config.Server.Transport.accept:
			server = TcpServer.fromStdin();
			break;
		case Config.Server.Transport.inet:
			server = new TcpServer();
			server.listen(serverConfig.listen.port, serverConfig.listen.addr);
			break;
		case Config.Server.Transport.unix:
		{
			server = new TcpServer();
			static if (is(UnixAddress))
			{
				string socketPath = serverConfig.listen.socketPath;
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

				addShutdownHandler({ socketPath.remove(); });
			}
			else
				throw new Exception("UNIX sockets are not available on this platform");
		}
	}

	addShutdownHandler({ server.close(); });

	server.handleAccept =
		(TcpConnection incoming)
		{
			handleConnection(incoming, incoming.localAddressStr, incoming.remoteAddressStr);
		};

	foreach (address; server.localAddresses)
		log.log("Listening on " ~ formatAddress(protocol, address) ~ " [" ~ to!string(address.addressFamily) ~ "]");
}
