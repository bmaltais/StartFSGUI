#!/usr/bin/env bash
# Behaviour of bin/startfsgui in demo mode: what it accepts, what it refuses, and that the real `startfs` is never reached.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
# Everything the CLI writes (config, launcher entry, command-line link) goes under one temporary home, never the real one.
export HOME XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME
HOME=$(mktemp -d)
XDG_CONFIG_HOME=$HOME/.config XDG_DATA_HOME=$HOME/.local/share XDG_CACHE_HOME=$HOME/.cache
export STARTFSGUI_DEMO=1
trap 'rm -rf "$HOME"' EXIT
fail=0
expect() { # <description> <pattern> <command...>
  local desc=$1 pattern=$2 out; shift 2
  out=$("$@" 2>&1)
  if [[ $out =~ $pattern ]]; then echo "ok   $desc"; else echo "FAIL $desc: got '$out'"; fail=1; fi
}
# The inner shells below load the library the way bin/startfsgui does; their single quotes are deliberate.
# shellcheck disable=SC2016
inner='source lib/common.sh; CONFIG_DIR=$XDG_CONFIG_HOME/startfsgui; source lib/demo.sh;'

expect "status is the fixture as JSON" '"filesystem":\{"name":"home"' bin/startfsgui status
expect "an older startfs, without --json, is read from its text" 'data: SAFE' \
  bash -c "$inner"'startfs() { [[ ${2:-} == --json ]] && return 2; echo "data: SAFE"; }; cmd_status'
expect "offer is accepted" '"ok":true' bin/startfsgui set offer 50G
expect "offer is written" '"offer_bytes":53687091200' bin/startfsgui status
expect "bad size refused" 'Not a size' bin/startfsgui set offer "ten gigs"
expect "copies accepted" '"ok":true' bin/startfsgui set copies 2
expect "copies 0 refused" 'from 1 to 9' bin/startfsgui set copies 0
expect "unknown setting refused" 'Unknown setting' bin/startfsgui set colour red
expect "other startfs commands refused in demo" 'demo mode refuses' bash -c "$inner"'startfs leave'

expect "nothing is on at first" '"launcher":false.*"done":false' bin/startfsgui integration
expect "setup turns the launcher and link on" '"ok":true' bin/startfsgui setup --launcher true --cli true --json
expect "the launcher entry is written under the temp home" 'Exec=' cat "$XDG_DATA_HOME/applications/startfsgui.desktop"
expect "integration reads it back" '"launcher":true.*"state":"ours".*"done":true' bin/startfsgui integration
expect "a bad flag value is refused" 'takes true or false' bin/startfsgui setup --launcher maybe --json
expect "window memory is saved" '"x":5,"y":-5' bash -c 'bin/startfsgui window --offset 5,-5'
expect "switching remember-position off forgets it" '"x":0,"y":0' bash -c 'bin/startfsgui setup --remember-position false --json >/dev/null; bin/startfsgui window'
expect "setup off removes the launcher" 'No such file' bash -c 'bin/startfsgui setup --launcher false --cli false --json >/dev/null; cat "$XDG_DATA_HOME/applications/startfsgui.desktop"'
expect "a node's version is read" '"version":"1.0.6","protocol":6' bin/startfsgui version --host mini2
expect "this node's version is read" '"version":"1.0.6"' bin/startfsgui version --host laptop --self
expect "an unreachable node says why" 'Connection timed out' bin/startfsgui version --host vps
expect "update runs the installer" 'Upgraded startfs 1.0.6 to 1.0.7' bin/startfsgui update --host mini2
expect "the node is on the new version" '"version":"1.0.7"' bin/startfsgui version --host mini2
expect "other nodes are untouched" '"version":"1.0.6"' bin/startfsgui version --host desktop
expect "updating a current node says so" 'already up to date' bin/startfsgui update --host mini2
expect "a pinned release is honoured" 'Upgraded startfs 1.0.6 to 1.0.8' bin/startfsgui update --host nas --version v1.0.8
expect "a failing node fails the update" 'Connection timed out' bin/startfsgui update --host vps
expect "an ssh option is not a host" 'not a host name' bin/startfsgui update --host -oProxyCommand=x
expect "a host with a shell character is refused" 'not a host name' bin/startfsgui version --host 'a;b'
expect "a bad release is refused" 'not a release' bin/startfsgui update --host mini2 --version latest
expect "stats lists every member, one that did not answer included" '"stats":null' bin/startfsgui stats
expect "stats carries the efficiency of a node" '"zstd_chunks":90' bin/startfsgui stats
expect "status carries the efficiency block" '"efficiency":\{"logical_bytes":12884901888' bin/startfsgui status
exit $fail
