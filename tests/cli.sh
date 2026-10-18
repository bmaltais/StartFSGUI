#!/usr/bin/env bash
# Behaviour of bin/startfsgui in demo mode: what it accepts, what it refuses, and that the real `startfs` is never reached.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
export XDG_CONFIG_HOME; XDG_CONFIG_HOME=$(mktemp -d)
export STARTFSGUI_DEMO=1
trap 'rm -rf "$XDG_CONFIG_HOME"' EXIT
fail=0
expect() { # <description> <pattern> <command...>
  local desc=$1 pattern=$2 out; shift 2
  out=$("$@" 2>&1)
  if [[ $out =~ $pattern ]]; then echo "ok   $desc"; else echo "FAIL $desc: got '$out'"; fail=1; fi
}
expect "status shows the fixture" 'data: SAFE' bin/startfsgui status
expect "offer is accepted" '"ok":true' bin/startfsgui set offer 50G
expect "offer is written" '50G offered' bin/startfsgui status
expect "bad size refused" 'Not a size' bin/startfsgui set offer "ten gigs"
expect "copies accepted" '"ok":true' bin/startfsgui set copies 2
expect "copies 0 refused" 'from 1 to 9' bin/startfsgui set copies 0
expect "unknown setting refused" 'Unknown setting' bin/startfsgui set colour red
# shellcheck disable=SC2016  # the single quotes are deliberate: the inner shell expands $XDG_CONFIG_HOME
expect "unknown startfs command refused in demo" 'demo mode refuses' bash -c 'source lib/common.sh; CONFIG_DIR=$XDG_CONFIG_HOME/startfsgui; source lib/demo.sh; startfs leave'
exit $fail
