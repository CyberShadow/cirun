cirun
=====

cirun is a stand-alone CI test runner for popular self-hosted software forges.

<img width="192" height="192" align="right" src="https://dump.thecybershadow.net/2cf05193d9eaa3ca9bbea83eb63a6381/cirun-13.svg">

- Single binary, download and run
- Build from source in one command
- Integrates with all popular software forges
- No dependencies, no containers<sup>1</sup>, no nonsense
- Does not need to run as a service
- Fully featured command-line interface
- *Optional* built-in web server for webhooks and light-weight, noscript-friendly status pages
- Integration with other web servers using UNIX sockets, CGI, and FastCGI


Compatibility
-------------

<table><tr>
    <th>Platforms</th>
    <th>Software forges</th>
    <th>Web servers</th>
  </tr><tr>
    <td><p></p><ul>
        <li>Linux   </li>
        <li>Windows   </li>
        <li>FreeBSD   </li>
        <li>macOS   </li>
    </ul></td><td><p></p><ul>
        <li>none (local git / command-line only)   </li>
        <li>none (remote git hook)   </li>
        <li>GitHub   </li>
        <li>GitLab   </li>
        <li>Gogs / Gitea   </li>
        <li>Gitolite   </li>
    </ul></td><td><p></p><ul>
        <li>none (CLI only)   </li>
        <li>built-in HTTP server   </li>
        <li>CGI   </li>
        <li>SCGI   </li>
        <li>FastCGI   </li>
    </ul></td>
</tr></table>

Additional integration options:

- Builds can be started from a webhook, git hook, or command-line
- Optional SSL support
- UNIX socket support for HTTP and FastCGI servers


Installation
------------

- Download a binary from the [GitHub releases page][releases] for your platform.

  Alternatively, run `dub run cirun` to fetch, build and run from source.

- To get started, run `cirun init`.  
  A template configuration file will be created for you to fill out.

- Instructions for integrating with software forge or web server software
  can be found on [the GitHub wiki][wiki].


Building from source
--------------------

1. Install the [Dub package manager](https://dub.pm/), which should be included with [a D compiler](https://dlang.org/download.html).
2. Run `dub build`.


Security
--------

By default, cirun executes the test script with the same privileges as itself.
Though cirun can be configured to run jobs securely
(i.e. allow safely testing pull requests from untrusted contributors),
**this is not the default configuration**.
Please check [the wiki][wiki] for some examples of isolating the test script to achieve this.

----

<sup>1: Though cirun does not require a container setup, it can still run your tests using containers.</sup>

  [releases]: https://github.com/CyberShadow/cirun/releases
  [wiki]: https://github.com/CyberShadow/cirun/wiki
