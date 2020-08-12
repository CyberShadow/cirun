#!/bin/bash
source ./lib.bash

# Git clone error.

"$cirun" run --wait repo 0123456789012345678901234567890123456789 --clone-url nxrepo 2>&1 | grep -F 'Status: errored (Clone failed with status'
