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
# <description> <jq filter> <command...>: passes when the command's JSON output makes the filter true.
expect_json() {
  local desc=$1 filter=$2 out; shift 2
  out=$("$@" 2>&1)
  if jq -e "$filter" <<<"$out" >/dev/null 2>&1; then echo "ok   $desc"; else echo "FAIL $desc: got '$out'"; fail=1; fi
}
DEMO=$XDG_CONFIG_HOME/startfsgui/demo
reset_demo() { rm -rf "$DEMO"; }
# Moves the update's start (and a forced restart's time) back, to play the demo clock forward without waiting for it.
age_upgrade() { local t s f; read -r t s f <"$DEMO/upgrade"; echo "$t $((s - $1))${f:+ $((f - $1))}" >"$DEMO/upgrade"; }
# The members' upgrade steps and releases, one short word each, to compare whole timelines.
steps() { bin/startfsgui status | jq -r '[.members[] | (.release[1:] + ":" + (.upgrade // "-"))] | join(" ")'; }
# The inner shells below load the library the way bin/startfsgui does; their single quotes are deliberate.
# shellcheck disable=SC2016
inner='source lib/common.sh; source lib/update.sh; CONFIG_DIR=$XDG_CONFIG_HOME/startfsgui; source lib/demo.sh;'

expect "status is the fixture as JSON" '"filesystem":\{"id":"[0-9a-f]+","name":"home","copies":3' bin/startfsgui status
expect "an older startfs, without --json, is read from its text" 'data: SAFE' \
  bash -c "$inner"'startfs() { [[ ${2:-} == --json ]] && return 2; echo "data: SAFE"; }; cmd_status'
expect "offer is accepted" '"ok":true' bin/startfsgui set offer 50G
expect "offer is written" '"offer_bytes":53687091200' bin/startfsgui status
expect "bad size refused" 'Not a size' bin/startfsgui set offer "ten gigs"
expect "copies accepted" '"ok":true' bin/startfsgui set copies 2
expect "copies 0 refused" 'from 1 to 9' bin/startfsgui set copies 0
expect "unknown setting refused" 'Unknown setting' bin/startfsgui set colour red
expect "other startfs commands refused in demo" 'demo mode refuses' bash -c "$inner"'startfs revoke abc'

expect "nothing is on at first" '"launcher":false.*"done":false' bin/startfsgui integration
expect "setup turns the launcher and link on" '"ok":true' bin/startfsgui setup --launcher true --cli true --json
expect "the launcher entry is written under the temp home" 'Exec=' cat "$XDG_DATA_HOME/applications/startfsgui.desktop"
expect "integration reads it back" '"launcher":true.*"state":"ours".*"done":true' bin/startfsgui integration
expect "a bad flag value is refused" 'takes true or false' bin/startfsgui setup --launcher maybe --json
expect "window memory is saved" '"x":5,"y":-5' bash -c 'bin/startfsgui window --offset 5,-5'
expect "switching remember-position off forgets it" '"x":0,"y":0' bash -c 'bin/startfsgui setup --remember-position false --json >/dev/null; bin/startfsgui window'
expect "setup off removes the launcher" 'No such file' bash -c 'bin/startfsgui setup --launcher false --cli false --json >/dev/null; cat "$XDG_DATA_HOME/applications/startfsgui.desktop"'
expect "a node's version is read" '"version":"1.10.1","protocol":15' bin/startfsgui version --host mini1
expect "this node's version is read" '"version":"1.10.2"' bin/startfsgui version --host laptop --self
expect "a down node says why" 'Connection timed out' bin/startfsgui version --host vps2
expect "install runs the installer" 'Upgraded startfs 1.10.1 to 1.10.3' bin/startfsgui install --host mini1
expect "the node is on the new version" '"version":"1.10.3"' bin/startfsgui version --host mini1
expect "other nodes are untouched" '"version":"1.10.2"' bin/startfsgui version --host desktop
expect "installing on a current node says so" 'already up to date' bin/startfsgui install --host mini1
expect "update is still an alias of install" 'already up to date' bin/startfsgui update --host mini1
expect "a pinned release is honoured" 'Upgraded startfs 1.10.2 to 1.10.0' bin/startfsgui install --host nas --version v1.10.0
expect "a failing node fails the install" 'Connection timed out' bin/startfsgui install --host vps2
expect "an ssh option is not a host" 'not a host name' bin/startfsgui install --host -oProxyCommand=x
expect "a host with a shell character is refused" 'not a host name' bin/startfsgui version --host 'a;b'
expect "a bad release is refused" 'not a release' bin/startfsgui install --host mini1 --version latest

echo "-- 1.10 shapes"
reset_demo
expect "stats lists every member, one that did not answer included" '"stats":null' bin/startfsgui stats
expect_json "stats has a row per member" 'length == 7 and (map(select(.stats == null)) | length) == 1' bin/startfsgui stats
expect "stats carries the efficiency of a node" '"zstd_chunks":5287' bin/startfsgui stats
expect "status carries the efficiency block" '"efficiency":\{"logical_bytes":5683210459' bin/startfsgui status
expect_json "status has the 1.10 top-level fields" 'has("stopping") and has("rechecking") and has("stranded") and has("tick_busy") and .filesystem.standin_days == 3 and .gc.purging == false and .upgrade.complete == false and .nodes == 7' bin/startfsgui status
expect_json "every member has every 1.10 field" 'all(.members[]; has("weight_bytes") and has("site") and has("standin_secs_left") and has("last_seen") and has("rtt_micros") and has("behind") and has("release") and has("protocol") and has("upgrade"))' bin/startfsgui status
expect_json "the cluster starts degraded with vps2 down" '.verdict == "Degraded" and .repair.degraded == 42 and (.members[] | select(.state == "Down") | .last_seen.secs_ago == 720 and .rtt_micros == null and .problem == "timed out")' bin/startfsgui status
expect_json "mini1 runs an older release" '[.members[] | select(.release == "v1.10.1") | .site] == ["home"]' bin/startfsgui status
expect_json "activity has the live shape" '.enabled and (.peers | length) == 6 and (.peers[] | select(.state == "Down") | .traffic == null) and .tick.busy_fraction > 0 and .resources.cgroup.memory_limit_bytes == null and (.chunk_sizes | length) == 6' bin/startfsgui activity
touch "$DEMO/healthy"
expect_json "healthy: vps2 is up and the verdict safe" '.verdict == "Safe" and .repair == null and ([.members[] | select(.state == "Online")] | length) == 7' bin/startfsgui status
expect_json "healthy: vps2 answers stats and activity" '(map(select(.stats == null)) | length) == 0' bin/startfsgui stats
rm "$DEMO/healthy"

echo "-- set"
reset_demo
expect_json "units are accepted, any case" '.ok' bin/startfsgui set offer 512mib
expect "512 MiB is written as bytes" '"offer_bytes":536870912' bin/startfsgui status
expect_json "a bare number is bytes" '.ok' bin/startfsgui set weight 4096
expect "weight shows in the self member" '"weight_bytes":4096' bin/startfsgui status
expect_json "weight 0 follows the offer" '.ok' bin/startfsgui set weight 0
expect_json "KiB, TB and B are units" '.ok' bash -c 'bin/startfsgui set offer 4KiB && bin/startfsgui set offer 2TB && bin/startfsgui set offer 7B'
expect "a decimal is refused" 'Not a size' bin/startfsgui set offer 1.5T
expect "a decimal weight is refused" 'Not a size' bin/startfsgui set weight 0.5G
expect "a bare unit is refused" 'Not a size' bin/startfsgui set offer G
expect "a negative size is refused" 'Not a size' bin/startfsgui set offer -5G
expect "a size with a command in it is refused" 'Not a size' bin/startfsgui set offer '5G; rm -rf /'
expect_json "a site is stored" '.ok' bin/startfsgui set site home-2.lab_a
expect "the site shows" '"site":"home-2.lab_a"' bin/startfsgui status
expect_json "an empty site clears it" '.ok' bin/startfsgui set site ""
expect_json "the cleared site is empty" '[.members[] | select(.is_self) | .site] == [""]' bin/startfsgui status
expect "a site with a space is refused" 'site name' bin/startfsgui set site "a b"
expect "a site with a quote is refused" 'site name' bin/startfsgui set site "a'b"
expect "a site of 65 characters is refused" 'site name' bin/startfsgui set site "$(printf 'a%.0s' {1..65})"
expect_json "a site of 64 characters is fine" '.ok' bin/startfsgui set site "$(printf 'a%.0s' {1..64})"
expect_json "activity off" '.ok' bin/startfsgui set activity off
expect_json "activity off nulls the traffic" '.enabled == false and all(.peers[]; .traffic == null)' bin/startfsgui activity
expect "activity takes on or off" 'on or off' bin/startfsgui set activity maybe
expect_json "activity on" '.ok' bin/startfsgui set activity on
expect "copies 10 refused" 'from 1 to 9' bin/startfsgui set copies 10
expect "copies text refused" 'from 1 to 9' bin/startfsgui set copies two
expect_json "copies above what can be stored is accepted with a warning" '.ok and (.warning | test("9 copies wanted but only 6"))' bin/startfsgui set copies 9
expect_json "the filesystem now wants 9 copies" '.filesystem.copies == 9 and .verdict == "Degraded"' bin/startfsgui status
bin/startfsgui set copies 3 >/dev/null
expect "set without a value is refused" 'needs a value' bin/startfsgui set offer
expect "set with an unknown option is refused" 'unknown option' bin/startfsgui set offer 1G --force
echo "-- set --host"
expect_json "a member's offer is set over ssh" '.ok' bin/startfsgui set offer 20G --host nas
expect_json "it shows on that member only" '([.members[] | select(.addr | startswith("nas")) | .offer_bytes] == [21474836480]) and ([.members[] | select(.is_self) | .offer_bytes] != [21474836480])' bin/startfsgui status
expect_json "a member's weight and site are set, by full name too" '.ok' bash -c 'bin/startfsgui set weight 10G --host nas.example.ts.net && bin/startfsgui set site garage --host nas'
expect_json "weight and site show on the member" '[.members[] | select(.addr | startswith("nas")) | [.weight_bytes, .site]] == [[10737418240, "garage"]]' bin/startfsgui status
expect "copies with --host is refused" 'not on another' bin/startfsgui set copies 2 --host nas
expect "activity with --host is refused" 'not on another' bin/startfsgui set activity off --host nas
expect "a bad host is refused" 'Not a host name' bin/startfsgui set offer 1G --host 'a;b'
expect "an ssh option is not a host" 'Not a host name' bin/startfsgui set offer 1G --host -oProxyCommand=x
expect "a bad size is refused before ssh" 'Not a size' bin/startfsgui set offer 1.5G --host nas
expect "a down member fails like ssh" '"ok":false.*Connection timed out' bin/startfsgui set offer 1G --host vps2
expect "a host that is not a member fails" '"ok":false.*Could not resolve' bin/startfsgui set offer 1G --host nowhere
# startfs's own refusal reaches the UI without its prefix, and a warning on success is passed along.
expect "startfs's words are passed on, without its prefix" '^\{"ok":false,"error":"nope, no"\}$' \
  bash -c "$inner"'startfs() { echo "startfs: nope, no" >&2; return 1; }; cmd_set copies 2'
expect "a warning on success is passed on" '"ok":true,"warning":"careful"' \
  bash -c "$inner"'startfs() { echo "warning: careful" >&2; }; cmd_set copies 2'
expect "the remote command quotes the value" "startfs config --site 'x'\$" \
  bash -c "$inner"'run_on() { echo "$2" >&2; return 1; }; cmd_set site x --host h 2>&1 | jq -r .error'

echo "-- upgrade"
reset_demo
expect_json "latest is the demo's newest release" '.ok and .release == "v1.10.3"' bin/startfsgui latest
expect_json "latest --refresh asks again" '.ok and .release == "v1.10.3"' bin/startfsgui latest --refresh
expect "latest refuses an unknown option" '"ok":false' bin/startfsgui latest --now
expect "a bad tag is refused" 'Not a release' bin/startfsgui upgrade 1.10.3
expect "upgrade --force with nothing under way is refused" 'no upgrade in progress' bin/startfsgui upgrade --force
expect "upgrade starts the cluster moving" '"message":"moving the cluster to v1.10.3: the members stage it' bin/startfsgui upgrade
expect_json "right after, every member that is up is staging" '[.members[] | select(.state == "Online") | .upgrade] | all(. == "Staging")' bin/startfsgui status
expect_json "the top-level upgrade is the target, not complete" '.upgrade == {release: "v1.10.3", lockstep: false, go: false, complete: false, split: []}' bin/startfsgui status
age_upgrade 3
expect "after 3 s the lowest id restarts, the rest are staged" '^1.10.2:Restarting 1.10.2:Staged 1.10.2:Staged 1.10.1:Staged 1.10.2:Staged 1.10.2:Staged 1.10.2:-$' steps
expect_json "a restarting member is Upgrading" '[.members[] | select(.upgrade == "Restarting") | .state] == ["Upgrading"]' bin/startfsgui status
age_upgrade 4
expect "then the next one, the first on the new release" '^1.10.3:- 1.10.2:Restarting' steps
age_upgrade 12
expect "this node waits on its mount, the others are done or staged" '^1.10.3:- 1.10.3:- 1.10.3:- 1.10.3:- 1.10.2:WaitingOnMount 1.10.2:Staged 1.10.2:-$' steps
age_upgrade 60
expect "it keeps waiting" 'WaitingOnMount' steps
expect_json "not complete while it waits" '.upgrade.complete == false' bin/startfsgui status
expect "upgrade --force carries on" '"ok":true,"message":"moving the cluster' bin/startfsgui upgrade --force
expect "this node restarts" '1.10.2:Restarting 1.10.2:Staged' steps
expect_json "and the daemon is stopping" '.stopping == true' bin/startfsgui status
age_upgrade 9
expect "then everything that is up is on the new release" '^1.10.3:- 1.10.3:- 1.10.3:- 1.10.3:- 1.10.3:- 1.10.3:- 1.10.2:-$' steps
expect_json "complete, though the down member stayed behind" '.upgrade.complete and .upgrade.release == "v1.10.3" and .stopping == false' bin/startfsgui status
expect "upgrading to the same release says so" 'already on v1.10.3; nothing to do' bin/startfsgui upgrade
expect "a tag can be named" 'moving the cluster to v1.10.4' bin/startfsgui upgrade v1.10.4
expect "asking again for the same tag does not start over" '^1.10.3:Staging' bash -c 'bin/startfsgui upgrade v1.10.4 >/dev/null; bin/startfsgui status | jq -r "[.members[] | (.release[1:] + \":\" + (.upgrade // \"-\"))] | join(\" \")"'

echo "-- remove, leave, purge, invite"
reset_demo
expect "an online member cannot be removed" 'member 0 is still online; it can leave with startfs leave' bin/startfsgui remove 0
expect "this node cannot remove itself" 'cannot remove itself; use leave' bin/startfsgui remove 15728644
expect "an unknown member is refused" 'no member 77' bin/startfsgui remove 77
expect "a member number is digits only" 'member number' bin/startfsgui remove '1;x'
expect "remove needs a number" 'member number' bin/startfsgui remove
expect "purge refuses while a member is down" '"ok":false.*cannot purge while a member is unreachable \(vps2.example.ts.net:7600\)' bin/startfsgui purge
expect "a down member is removed" '^\{"ok":true\}$' bin/startfsgui remove 15728648
expect_json "it is gone from status" '.nodes == 6 and .verdict == "Safe" and ([.members[] | select(.addr | startswith("vps2"))] | length) == 0' bin/startfsgui status
expect_json "and from stats" 'length == 6' bin/startfsgui stats
expect_json "and from activity" '(.peers | length) == 5' bin/startfsgui activity
expect "purge starts" '"message":"purge started on 6 member\(s\)' bin/startfsgui purge
expect_json "purging shows for a while" '.gc.purging == true' bin/startfsgui status
echo $(($(date +%s) - 20)) >"$DEMO/purge_until"
expect_json "then stops" '.gc.purging == false' bin/startfsgui status
expect_json "invite gives the join command" '.ok and (.command | test("^startfs join startfs1-demo[0-9a-f]+$")) and (has("copied") | not)' bin/startfsgui invite
expect_json "invite --copy says it copied" '.ok and .copied == true' bin/startfsgui invite --copy
expect "invite refuses an unknown option" '"ok":false' bin/startfsgui invite --paste
expect_json "invite --copy without wl-copy still gives the command" '.ok and .copied == false and (.command | startswith("startfs join "))' \
  bash -c "$inner"'unset -f clipboard_copy; clipboard_copy() { return 1; }; cmd_invite --copy'
expect "leave says it is handing over" '"message":"leaving: this node.s data is being handed to the others"' bin/startfsgui leave
expect_json "this node is Leaving" '.node_state == "Leaving" and ([.members[] | select(.is_self) | .state] == ["Leaving"])' bin/startfsgui status

echo "-- logs"
fakebin=$(mktemp -d)
printf '#!/bin/sh\necho "$@" >"%s/ran"\n' "$fakebin" >"$fakebin/xdg-terminal-exec"
chmod +x "$fakebin/xdg-terminal-exec"
expect "logs opens the default terminal, detached" '"ok":true' env PATH="$fakebin:$PATH" bin/startfsgui logs
for _ in 1 2 3 4 5 6 7 8 9 10; do [[ -f $fakebin/ran ]] && break; sleep 0.2; done
expect "it runs the demo's stand-in, not the real journal" 'startfsgui-logs.*demo: journalctl' cat "$fakebin/ran"
rm -rf "$fakebin"; mkdir -p "$fakebin"; for c in jq readlink dirname mkdir cat; do ln -s "$(command -v $c)" "$fakebin/$c"; done
expect "logs with no terminal at all is an error" '"ok":false' env -u TERMINAL PATH="$fakebin" "$(command -v bash)" bin/startfsgui logs
rm -rf "$fakebin"
echo "-- latest, with the network faked"
reset_demo
export STARTFSGUI_DEMO=
# A stand-in for the network, and a cache in the temporary cache dir. The demo's own latest is not loaded here.
latest_inner='source lib/common.sh; source lib/update.sh;'
fake='latest_fetch() { echo "$FAKE_TAG"; };'
expect "the first lookup asks and answers" '"release":"v1.10.9"' env FAKE_TAG=v1.10.9 bash -c "$latest_inner$fake"'cmd_latest'
expect "it is cached" '"release":"v1.10.9"' cat "$XDG_CACHE_HOME/startfsgui/latest.json"
expect "a second lookup within 6 hours uses the cache" '"release":"v1.10.9"' env FAKE_TAG=v1.10.10 bash -c "$latest_inner$fake"'cmd_latest'
expect "--refresh ignores the cache" '"release":"v1.10.10"' env FAKE_TAG=v1.10.10 bash -c "$latest_inner$fake"'cmd_latest --refresh'
jq '.fetched_at -= 30000' "$XDG_CACHE_HOME/startfsgui/latest.json" >"$XDG_CACHE_HOME/l.tmp" && mv "$XDG_CACHE_HOME/l.tmp" "$XDG_CACHE_HOME/startfsgui/latest.json"
expect "a cache older than 6 hours is asked again" '"release":"v1.11.0"' env FAKE_TAG=v1.11.0 bash -c "$latest_inner$fake"'cmd_latest'
expect "offline, an older answer is still given" '^\{"ok":true,"release":"v1.11.0"\}$' bash -c "$latest_inner"'latest_fetch() { return 1; }; cmd_latest --refresh'
expect "a reply that is not a release tag is not believed" '"release":"v1.11.0"' env FAKE_TAG='<html>' bash -c "$latest_inner$fake"'cmd_latest --refresh'
rm -rf "$XDG_CACHE_HOME/startfsgui"
expect "offline with no cache is an error" '^\{"ok":false,"error":".+"\}$' bash -c "$latest_inner"'latest_fetch() { return 1; }; cmd_latest'
export STARTFSGUI_DEMO=1
exit $fail
