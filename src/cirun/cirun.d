/**
 * Entry point.
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

module cirun.cirun;

import ae.utils.main;
import ae.sys.net.ae;

import cirun.cli.cli;

mixin main!cliEntryPoint;
