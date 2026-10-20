# shellcheck shell=bash
# Demo mode: a fixture cluster and no contact with the real daemon. Loaded by bin/startfsgui only when STARTFSGUI_DEMO=1 or
# $CONFIG_DIR/demo/ENABLED exists. The test session shares your user, so without this a click there would reconfigure the live
# cluster. `startfs` is shadowed by a function that answers like StartFS 1.10.2 (same JSON, same refusals), and `run_on` and the
# clipboard are shadowed too, so nothing leaves this machine. What the commands change is kept in files under $DEMO_DIR.
#
# The cluster: seven members, laptop (this node), desktop, nas, mini1 (still on v1.10.1), ocilab1, vps1 and vps2. vps2 is down, so
# the verdict is Degraded, until `touch $DEMO_DIR/healthy` brings it back (a test's all-clear). `rm -rf $DEMO_DIR` (that is,
# ~/.config/startfsgui/demo) puts everything back as it was.
#
# Files in $DEMO_DIR:
#   hosts/<name>/{offer,weight,site}  what `config` or `set --host` changed, per member (bytes for the sizes)
#   copies, activity                  the filesystem's copies, this node's counters (on|off)
#   upgrade                           "<tag> <start epoch> [<forced epoch>]" of the update in progress or finished
#   releases.json                     what each member ran before that update, by name
#   removed, leaving, purge_until, healthy, versions/  members removed, node leaving, purge end time, all-clear, installer demo

readonly DEMO_DIR="$CONFIG_DIR/demo"
readonly DEMO_TAG="v1.10.3"
readonly DEMO_STAGE_SECS=3
readonly DEMO_RESTART_SECS=4
readonly DEMO_PURGE_SECS=10
mkdir -p "$DEMO_DIR"

# What each member is called, how it is reached and what it offers before anyone changes it.
readonly DEMO_MEMBERS_JQ='
def gib: . * 1073741824;
def base: [
  {n: "desktop", id: 0, site: "home", offer: (100 | gib), rtt: 2300, rel: "v1.10.2"},
  {n: "nas", id: 2, site: "home", offer: (20 | gib), rtt: 4100, rel: "v1.10.2"},
  {n: "ocilab1", id: 15728642, site: "cloud", offer: (100 | gib), rtt: 33128, rel: "v1.10.2"},
  {n: "mini1", id: 15728643, site: "home", offer: (100 | gib), rtt: 6857, rel: "v1.10.1"},
  {n: "laptop", id: 15728644, site: "home", offer: (100 | gib), rtt: null, rel: "v1.10.2"},
  {n: "vps1", id: 15728647, site: "cloud", offer: (50 | gib), rtt: 10800, rel: "v1.10.2"},
  {n: "vps2", id: 15728648, site: "cloud", offer: (50 | gib), rtt: 11389, rel: "v1.10.2"}];

# The rolling upgrade as of $t seconds after `update`: everyone stages for a few seconds, then the members that are up restart one
# at a time, lowest id first. The node the GUI runs on cannot restart while its mount is in use until it is forced ($f).
def sim($t; $f; $tag):
  reduce .[] as $m ({cur: 3, blocked: false, out: []};
    . as $s
    | if $m.state != "Online" or $m.release == $tag then .out += [$m]
      elif $t < 3 then .out += [$m | .upgrade = "Staging"]
      elif $s.blocked then .out += [$m | .upgrade = "Staged"]
      else
        (if $m.is_self then (if $f == null then null else ([$s.cur, $f] | max) end) else $s.cur end) as $start
        | if $start == null then
            .blocked = true | .out += [$m | .upgrade = (if $t >= $s.cur then "WaitingOnMount" else "Staged" end)]
          elif $t < $start then
            .out += [$m | .upgrade = (if $m.is_self and $t >= $s.cur then "WaitingOnMount" else "Staged" end)] | .cur = $start + 4
          elif $t < $start + 4 then
            .out += [$m | .state = "Upgrading" | .upgrade = "Restarting"] | .cur = $start + 4
          else
            .out += [$m | .release = $tag] | .cur = $start + 4
          end
      end) | .out;

[base[] | select(.n as $n | $removed | index($n) | not)
  | . as $m
  | ($ov[$m.n] // {}) as $o
  | ($m.n == "vps2" and ($healthy | not)) as $down
  | {n: $m.n, id: $m.id, addr: ($m.n + ".example.ts.net:7600"),
     state: (if $down then "Down" elif $m.n == "laptop" and $leaving then "Leaving" else "Online" end),
     offer_bytes: (($o.offer // $m.offer) | tonumber), weight_bytes: (($o.weight // 0) | tonumber), site: ($o.site // $m.site),
     is_self: ($m.n == "laptop"), problem: (if $down then "timed out" else null end), standin_secs_left: null,
     last_seen: (if $down then {secs_ago: 720, exact: true} else null end),
     rtt_micros: (if $down or $m.n == "laptop" then null else $m.rtt end), behind: null,
     release: ($rel[$m.n] // $m.rel), protocol: 15, upgrade: null}]
| if $up == null then . else sim($up.t; $up.f; $up.tag) end
'

# Reads one of the state files, or a default.
demo_get() { local f="$DEMO_DIR/$1"; if [[ -f $f ]]; then cat "$f"; else printf '%s' "$2"; fi; }

# {"desktop": {"offer": "...", ...}, ...} from hosts/*/*. Each value is one line (a cleared site is an empty line, not no file).
demo_overrides() {
  { grep -rH '' "$DEMO_DIR/hosts" 2>/dev/null || true; } | jq -Rn --arg root "$DEMO_DIR/hosts/" '
    reduce (inputs | select(startswith($root)) | ltrimstr($root) | capture("^(?<h>[^/]+)/(?<k>[a-z]+):(?<v>.*)$")) as $e
      ({}; .[$e.h][$e.k] = $e.v)'
}

# The members as `status` lists them (plus "n", their short name), upgrade progress included.
demo_members() {
  local up=null tag start forced f=null now=$EPOCHSECONDS
  if [[ -f $DEMO_DIR/upgrade ]]; then
    read -r tag start forced <"$DEMO_DIR/upgrade"
    [[ -z ${forced:-} ]] || f=$((forced - start))
    up=$(jq -nc --arg tag "$tag" --argjson t $((now - start)) --argjson f "$f" '{tag: $tag, t: $t, f: $f}')
  fi
  jq -nc --argjson ov "$(demo_overrides)" --argjson rel "$(demo_get releases.json '{}')" \
    --argjson removed "$(jq -Rsc 'split("\n") | map(select(length > 0))' <<<"$(demo_get removed '')")" \
    --argjson healthy "$([[ -f $DEMO_DIR/healthy ]] && echo true || echo false)" \
    --argjson leaving "$([[ -f $DEMO_DIR/leaving ]] && echo true || echo false)" --argjson up "$up" "$DEMO_MEMBERS_JQ"
}

# The fixture as `startfs status --json` prints it (StartFS 1.10.2's shape, every field present).
demo_json() {
  local copies purge_until
  copies=$(demo_get copies 3) purge_until=$(demo_get purge_until 0)
  demo_members | jq -c --argjson copies "$copies" --argjson now "$EPOCHSECONDS" --argjson purge_until "$purge_until" \
    --argjson up "$([[ -f $DEMO_DIR/upgrade ]] && echo true || echo false)" --arg tag "$(demo_get upgrade 'v1.10.2' | cut -d' ' -f1)" '
    . as $all
    | ($all[] | select(.is_self)) as $me
    | [$all[] | select(.state != "Down" and .offer_bytes > 0)] as $givers
    | ([$copies, ($givers | length)] | min) as $possible
    | ($all | any(.[]; .state == "Down")) as $down
    | {stopping: ($me.upgrade == "Restarting"),
       verdict: (if $down then "Degraded" elif $possible < $copies then "BestEffort" else "Safe" end),
       filesystem: {id: "1d0fbb9bf5b2f81b499e168e56613cac", name: "home", copies: $copies, copies_rev: 1, repair_grace_secs: 1800,
                    gc_retention_secs: 604800, standin_days: 3},
       node_state: $me.state,
       usage: {chunks: 6285, stored_bytes: 1153513149, offer_bytes: $me.offer_bytes},
       efficiency: {logical_bytes: 5683210459, referenced_bytes: 4946234997, inline_bytes: 7460623, local_plain_bytes: 2620489135,
                    local_disk_bytes: 1153513149, raw_chunks: 998, zstd_chunks: 5287, zstd_plain_bytes: 2084491039},
       staging: {chunks: 0, bytes: 0}, cache: {chunks: 1534, used_bytes: 152133336, capacity_bytes: 1073741824},
       members: ($all | map(del(.n))),
       upgrade: (if $up then {release: $tag, lockstep: false, go: false,
                              complete: ($all | all(.[] | select(.state == "Online" or .state == "Upgrading"); .release == $tag)), split: []}
                 else {release: "v1.10.2", lockstep: null, go: false,
                       complete: ($all | all(.[] | select(.state == "Online"); .release == "v1.10.2")), split: []} end),
       nodes: ($all | length), copies_possible: $possible,
       usable_bytes: (($all | map(.offer_bytes) | add) / $copies | floor),
       unreplicated: (if $down then [{copies: 2, chunks: 42}] else [] end),
       repair: (if $down then {at_risk: 0, degraded: 42} else null end),
       rechecking: 0, unheard: [], stranded: [],
       scrub: {state: "Idle", last_pass: 1792267430192000000, next_pass: 1794859430192000000, remaining: 0, healing: 0},
       log: {entries: 0, objects: 35050},
       gc: {pending_chunks: 0, pending_bytes: 0, reclaimed_chunks: 2, reclaimed_bytes: 531708, waiting_on: [],
            purging: ($now < $purge_until)},
       warnings: (if $possible < $copies then
                    ["redundancy: \($copies) wanted, \($possible) possible (only \($possible) node(s) can store copies)"] else [] end),
       conflicts: [], tick_busy: null}'
}

# The fixture as `startfs stats --json` prints it; vps2 does not answer while it is down.
demo_stats() {
  demo_members | jq -c '
    def row: {"desktop": [6322, 1153644176, 2632973887, 1028, 5294], "nas": [1710, 317000000, 700000000, 410, 1300],
              "ocilab1": [6410, 1160000000, 2650000000, 1011, 5399], "mini1": [6120, 1121000000, 2560000000, 990, 5130],
              "laptop": [6285, 1153513149, 2620489135, 998, 5287], "vps1": [3140, 575000000, 1310000000, 500, 2640],
              "vps2": [3160, 579000000, 1320000000, 505, 2655]}[.n];
    [.[] | . as $m | row as $r
     | {member: .id, addr: .addr, is_self: .is_self,
        stats: (if .state == "Down" then null else
          {usage: {chunks: $r[0], stored_bytes: $r[1], offer_bytes: .offer_bytes},
           efficiency: {logical_bytes: 5683210459, referenced_bytes: 4946234997, inline_bytes: 7460623, local_plain_bytes: $r[2],
                        local_disk_bytes: $r[1], raw_chunks: $r[3], zstd_chunks: $r[4], zstd_plain_bytes: ($r[2] * 0.8 | floor)},
           pending_gc_bytes: 0} end)}]'
}

# The fixture as `startfs activity --json` prints it. The numbers move with the clock so a refresh visibly changes them; the
# same clock makes some peers busy with chunks and the rest quiet.
demo_activity() {
  local enabled=true
  [[ $(demo_get activity on) == on ]] || enabled=false
  demo_members | jq -c --argjson n "$EPOCHSECONDS" --argjson enabled "$enabled" '
    def v($salt; $mod): (($n * 7919 + $salt * 104729) % $mod);
    def cat($b; $m): {bytes: $b, messages: $m};
    def traffic($i):
      (if ((($n / 5 | floor) + $i) % 3) == 0 then 0 else v($i; 400000) + 20000 end) as $c
      | (if ((($n / 7 | floor) + $i) % 4) == 0 then 0 else v($i + 9; 9000) + 600 end) as $meta
      | {sent: {chunk: cat($c; ($c / 65536 | ceil)), metadata: cat($meta; ($meta / 400 | ceil)),
                gossip: cat(13812 + ($n % 11) * 31; 60), other: cat(300; 12)},
         received: {chunk: cat(($c * 3 / 4 | floor); ($c / 80000 | ceil)), metadata: cat(($meta * 2 / 3 | floor); ($meta / 500 | ceil)),
                    gossip: cat(12661 + ($n % 13) * 27; 55), other: cat(275; 11)},
         acknowledged: ($c / 65536 | ceil), timed_out: (if .state == "Down" then 3 else 0 end),
         retried: (if .state == "Down" then 2 else 0 end)};
    [.[] | select(.is_self | not)] as $peers
    | {enabled: $enabled, window_secs: 60.0,
       peers: [range(0; $peers | length) as $i | $peers[$i] | . as $p
               | {member: .id, addr: .addr, state: .state, in_flight: (if .state == "Down" then 0 else v($i; 3) end),
                  traffic: (if $enabled and .state != "Down" then traffic($i) else null end)}],
       tick: (if $enabled then {ticks: (5896 + $n % 60), avg_ms: (0.15 + v(1; 100) / 1000), max_ms: (40 + v(2; 3000) / 100),
                                avg_phase_ms: {flush: 0.0357, sync: 0.1134, receive: 0.00126, gossip: 0.0039, replicate: 0.0067, other: 0.037},
                                busy_fraction: (0.015 + v(3; 80) / 10000)} else null end),
       queue: {chunks: (v(4; 5) * 3), oldest_secs: (if v(4; 5) == 0 then null else v(5; 20) end)},
       chunk_sizes: [{up_to_bytes: 4096, chunks: 0}, {up_to_bytes: 16384, chunks: 2}, {up_to_bytes: 65536, chunks: 5},
                     {up_to_bytes: 262144, chunks: 1}, {up_to_bytes: 1048576, chunks: 0}, {up_to_bytes: null, chunks: 0}],
       structures: {inbox: {entries: 0, bytes: 0, limit_bytes: null},
                    chunk_replies: {entries: 0, bytes: 0, limit_bytes: 16777216},
                    decoded_cache: {entries: 30, bytes: 535796, limit_bytes: 134217728},
                    replication_index: {entries: 0, bytes: null, limit_bytes: null},
                    staging_index: {entries: 0, bytes: null, limit_bytes: null}},
       resources: {rss_bytes: (95686656 + v(6; 4000000)), cpu_secs: (29.76 + ($n % 1000) / 10), threads: 9,
                   mem_available_bytes: 69482778624, swap_used_bytes: 711602176,
                   memory_pressure: {avg10: 0.0, avg60: 0.0}, cpu_pressure: {avg10: 0.0, avg60: 0.17},
                   io_pressure: {avg10: 0.0, avg60: 0.0}, written_bytes: (44470272 + $n % 100000 * 1000),
                   cgroup: {memory_current_bytes: 107053056, memory_limit_bytes: null}}}'
}

# demo_bytes SIZE: the size in bytes, or startfs's refusal. Integers only, as in the real parser.
demo_bytes() {
  local s=${1^^} n m=1
  [[ $s =~ ^([0-9]+)(B|[KMGT](I?B)?)?$ ]] || { echo "startfs: not a size: $1" >&2; return 1; }
  n=${BASH_REMATCH[1]}
  case ${BASH_REMATCH[2]:0:1} in K) m=1024 ;; M) m=1048576 ;; G) m=1073741824 ;; T) m=1099511627776 ;; *) ;; esac
  jq -nr --arg n "$n" --argjson m "$m" '($n | tonumber) * $m | if . > 9e15 then empty else floor | tostring end' \
    | grep . || { echo "startfs: not a size: $1" >&2; return 1; }
}

# demo_store <member name> <offer|weight|site> <value>: remembers one setting of one member.
demo_store() {
  mkdir -p "$DEMO_DIR/hosts/$1"
  echo "$3" >"$DEMO_DIR/hosts/$1/$2"
}

# How many members can take copies, for the warning `config --copies` gives.
demo_possible() { demo_members | jq '[.[] | select(.state != "Down" and .offer_bytes > 0)] | length'; }

# demo_config <member name> <flags...>: `startfs config` for this node (laptop) or, over run_on, another.
demo_config() {
  local name=$1 b possible
  shift
  while (($#)); do
    (($# >= 2)) || { echo "startfs: missing value for $1" >&2; return 1; }
    case $1 in
      --offer | --weight)
        b=$(demo_bytes "$2") || return 1
        demo_store "$name" "${1#--}" "$b" ;;
      --site) demo_store "$name" site "$(sed 's/^[[:space:]]*//;s/[[:space:]]*$//' <<<"$2")" ;;
      --activity)
        [[ $2 == on || $2 == off ]] || { echo "startfs: --activity must be on or off" >&2; return 1; }
        echo "$2" >"$DEMO_DIR/activity" ;;
      --copies)
        [[ $2 =~ ^[0-9]+$ ]] || { echo "startfs: --copies must be a number" >&2; return 1; }
        (($2 >= 1)) || { echo "startfs: need a name and at least 1 copy" >&2; return 1; }
        echo "$2" >"$DEMO_DIR/copies"
        possible=$(demo_possible)
        if (($2 > possible)); then
          echo "warning: $2 copies wanted but only $possible node(s) can store copies, so $possible will exist until more join" >&2
        fi ;;
      *) echo "startfs: unexpected argument $1" >&2; return 1 ;;
    esac
    shift 2
  done
}

# demo_update [tag] [--force]: records the new target and when it started; demo_members plays the rest out from the clock.
demo_update() {
  local tag="" force=0 current rel start forced
  while (($#)); do
    case $1 in
      --force) force=1 ;;
      v[0-9]*) tag=$1 ;;
      *) echo "startfs: $1 is not a release tag (expected something like v1.10.0)" >&2; return 1 ;;
    esac
    shift
  done
  if [[ $force == 1 && -z $tag ]]; then
    [[ -f $DEMO_DIR/upgrade ]] || { echo "startfs: no upgrade in progress" >&2; return 1; }
    read -r tag start forced <"$DEMO_DIR/upgrade"
    [[ -n ${forced:-} ]] || echo "$tag $start $EPOCHSECONDS" >"$DEMO_DIR/upgrade"
  else
    tag=${tag:-$DEMO_TAG}
    current=$(demo_members)
    if jq -e --arg t "$tag" 'all(.[] | select(.state == "Online"); .release == $t)' <<<"$current" >/dev/null; then
      echo "the cluster is already on $tag; nothing to do"
      return 0
    fi
    # Asking again for the target already under way carries on; it does not start over.
    if [[ -f $DEMO_DIR/upgrade && $(cut -d' ' -f1 "$DEMO_DIR/upgrade") == "$tag" ]]; then
      echo "moving the cluster to $tag: the members stage it, then restart (see startfs status)"
      return 0
    fi
    # What runs now becomes the starting point of the new update.
    rel=$(jq -c 'map({(.n): .release}) | add' <<<"$current")
    echo "$rel" >"$DEMO_DIR/releases.json"
    echo "$tag $EPOCHSECONDS$([[ $force == 0 ]] || echo " $EPOCHSECONDS")" >"$DEMO_DIR/upgrade"
  fi
  echo "moving the cluster to $tag: the members stage it, then restart (see startfs status)"
}

# demo_remove N: only a member that is down can be dropped, as in the real thing.
demo_remove() {
  local row
  [[ ${1:-} =~ ^[0-9]+$ ]] || { echo "startfs: remove needs a member number (see startfs status)" >&2; return 1; }
  row=$(demo_members | jq -c --argjson id "$1" '.[] | select(.id == $id)')
  [[ -n $row ]] || { echo "startfs: no member $1" >&2; return 1; }
  [[ $(jq -r .is_self <<<"$row") == false ]] || { echo "startfs: this node cannot remove itself; use leave" >&2; return 1; }
  [[ $(jq -r .state <<<"$row") == Down ]] || { echo "startfs: member $1 is still online; it can leave with startfs leave" >&2; return 1; }
  jq -r .n <<<"$row" >>"$DEMO_DIR/removed"
}

demo_purge() {
  local down count
  down=$(demo_members | jq -r '[.[] | select(.state == "Down") | .addr] | join(", ")')
  if [[ -n $down ]]; then
    echo "startfs: cannot purge while a member is unreachable ($down): it would keep its copies and hand them back to the others when it returns; bring it back, or startfs remove it if it is gone for good" >&2
    return 1
  fi
  count=$(demo_members | jq length)
  echo $((EPOCHSECONDS + DEMO_PURGE_SECS)) >"$DEMO_DIR/purge_until"
  echo "purge started on $count member(s); deleted files' data is freed as each member allows (see startfs status)"
}

startfs() {
  case ${1:-} in
    stats) [[ ${2:-} == --json ]] && demo_stats ;;
    activity) [[ ${2:-} == --json ]] && demo_activity ;;
    status) [[ ${2:-} == --json ]] && demo_json ;;
    config) shift; demo_config laptop "$@" ;;
    update) shift; demo_update "$@" ;;
    remove) shift; demo_remove "$@" ;;
    purge) demo_purge ;;
    leave)
      touch "$DEMO_DIR/leaving"
      echo "leaving: this node's data is being handed to the others" ;;
    token)
      [[ ${2:-} == --example ]] || { echo "startfsgui: demo mode refuses to run 'startfs token'" >&2; return 1; }
      echo "startfs join startfs1-demo$(od -An -N12 -tx1 /dev/urandom | tr -d ' \n')" ;;
    *) echo "startfsgui: demo mode refuses to run 'startfs ${1:-}'" >&2; return 1 ;;
  esac
}

# Nothing reaches the clipboard or the network in a demo.
clipboard_copy() { return 0; }
latest_cache_file() { printf '%s' "$DEMO_DIR/latest.json"; }
latest_fetch() { echo "$DEMO_TAG"; }
logs_command() { printf '%s' 'echo "demo: journalctl --user -u startfs -f"; sleep 30'; }

# ---- ssh: nothing is run anywhere ---------------------------------------------------------------
# run_on answers what lib/common.sh and lib/update.sh send: `startfs config` on another member, `startfs --version`, and the
# installer. vps2 cannot be reached while it is down, like the real one.
demo_known() { case $1 in desktop | nas | ocilab1 | mini1 | laptop | vps1 | vps2) return 0 ;; *) return 1 ;; esac; }
demo_version() { # <short name>: the version and protocol a node reports until the installer "updates" it
  local f="$DEMO_DIR/versions/$1"
  if [[ -f $f ]]; then cat "$f"; elif [[ $1 == mini1 ]]; then echo "1.10.1 15"; else echo "1.10.2 15"; fi
}
run_on() { # <host|""> <command>
  local host=${1:-laptop} cmd=$2 short v p
  short=${host%%.*}
  if [[ $short == vps2 && ! -f $DEMO_DIR/healthy ]]; then
    echo "ssh: connect to host $host port 22: Connection timed out" >&2
    return 255
  fi
  mkdir -p "$DEMO_DIR/versions"
  case $cmd in
    *"startfs config --"*)
      demo_known "$short" || { echo "ssh: Could not resolve hostname $host: Name or service not known" >&2; return 255; }
      [[ $cmd =~ startfs\ config\ (--[a-z]+)\ \'([^\']*)\' ]] || { echo "startfs: unexpected argument" >&2; return 1; }
      demo_config "$short" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" ;;
    *"startfs --version"*) read -r v p <<<"$(demo_version "$short")"; echo "startfs $v (protocol $p)" ;;
    *STARTFS_VERSION=*) v=${cmd#*STARTFS_VERSION=}; v=${v%% *}; v=${v#v}; demo_install "$short" "$v" ;;
    *) demo_install "$short" "${DEMO_TAG#v}" ;;
  esac
}
demo_install() { # <short name> <version>
  local cur; read -r cur _ <<<"$(demo_version "$1")"
  if [[ $cur == "$2" ]]; then echo "install: startfs $cur is already up to date"; return 0; fi
  echo "install: Downloading startfs-v$2-x86_64-linux"
  sleep 0.4; echo "install: Checksum verified"
  sleep 0.4; echo "install: Stopped startfs.service, replaced the binary (old one kept as startfs.prev)"
  sleep 0.4; echo "install: Started startfs.service; the daemon answers"
  echo "$2 15" >"$DEMO_DIR/versions/$1"
  echo "install: Upgraded startfs $cur to $2"
}
