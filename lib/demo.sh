# shellcheck shell=bash
# Demo mode: a fixture cluster and no contact with the real daemon. Loaded by bin/startfsgui only when STARTFSGUI_DEMO=1 or
# $CONFIG_DIR/demo/ENABLED exists. The test session shares your user, so without this a click there would reconfigure the live
# cluster. `startfs` is shadowed by a function: status is answered from the fixture below, `config` is recorded in a file.

readonly DEMO_DIR="$CONFIG_DIR/demo"
mkdir -p "$DEMO_DIR"
[[ -f $DEMO_DIR/offer ]] || echo "10.0 GiB" >"$DEMO_DIR/offer"
[[ -f $DEMO_DIR/copies ]] || echo 3 >"$DEMO_DIR/copies"

# The fixture as `startfs status --json` prints it. Sizes are in bytes, so the offer is read back from the text form's "10.0 GiB".
demo_json() {
  local offer copies
  offer=$(<"$DEMO_DIR/offer"); copies=$(<"$DEMO_DIR/copies")
  jq -nc --arg offer "$offer" --argjson copies "$copies" '
    def gib: . * 1073741824;
    ($offer | sub(" GiB$"; "") | sub("G$"; "") | tonumber | gib | floor) as $o
    | {verdict: "Safe", filesystem: {name: "home", copies: $copies}, node_state: "Online",
       usage: {chunks: 169, stored_bytes: 10905190, offer_bytes: $o}, staging: {chunks: 0, bytes: 0},
       efficiency: {logical_bytes: (12 | gib), referenced_bytes: (6 | gib), inline_bytes: 0, local_plain_bytes: (3 | gib),
                    local_disk_bytes: (2 | gib), raw_chunks: 10, zstd_chunks: 90},
       cache: {chunks: 12, used_bytes: 2831155, capacity_bytes: 1073741824},
       members: [
         {id: 0, addr: "laptop.example.ts.net:7600", state: "Online", offer_bytes: $o, is_self: true, problem: null},
         {id: 1, addr: "desktop.example.ts.net:7600", state: "Online", offer_bytes: (10 | gib), is_self: false, problem: null},
         {id: 2, addr: "nas.example.ts.net:7600", state: "Online", offer_bytes: (100 | gib), is_self: false, problem: null},
         {id: 3, addr: "vps.example.ts.net:7600", state: "Down", offer_bytes: (100 | gib), is_self: false, problem: "timed out"}],
       nodes: 4, copies_possible: $copies, usable_bytes: (40 | gib), unreplicated: [], repair: null, unheard: [],
       scrub: {state: "Idle"}, log: {entries: 1, objects: 6720}, gc: {pending_chunks: 0}, warnings: [], conflicts: []}'
}

# The fixture as `startfs stats --json` prints it; the node called vps does not answer.
demo_stats() {
  jq -nc '
    def gib: . * 1073741824;
    def eff($plain; $disk): {logical_bytes: (12 | gib), referenced_bytes: (6 | gib), inline_bytes: 0, local_plain_bytes: ($plain | gib),
                             local_disk_bytes: ($disk | gib), raw_chunks: 10, zstd_chunks: 90};
    def node($m; $addr; $self; $used; $plain; $offer):
      {member: $m, addr: $addr, is_self: $self, stats: {usage: {chunks: 700, stored_bytes: ($used | gib), offer_bytes: ($offer | gib)},
       efficiency: eff($plain; $used), pending_gc_bytes: 0}};
    [node(0; "laptop.example.ts.net:7600"; true; 2; 3; 10), node(1; "desktop.example.ts.net:7600"; false; 3; 4.5; 10),
     node(2; "nas.example.ts.net:7600"; false; 5; 7.5; 100),
     {member: 3, addr: "vps.example.ts.net:7600", is_self: false, stats: null}]'
}

startfs() {
  case ${1:-} in
    stats) demo_stats ;;
    status)
      [[ ${2:-} == --json ]] && { demo_json; return; }
      cat <<STATUS
data: SAFE
filesystem: home ($(<"$DEMO_DIR/copies") copies)
node: online
usage: 10.4 MiB stored in 169 chunks, $(<"$DEMO_DIR/offer") offered
redundancy: $(<"$DEMO_DIR/copies") of $(<"$DEMO_DIR/copies") copies possible (4 nodes)
usable: about 40.0 GiB
cache: 2.7 MiB used of 1.0 GiB
members:
  0         laptop.example.ts.net:7600   up    10.0 GiB offered  (this node)
  1         desktop.example.ts.net:7600  up    10.0 GiB offered
  2         nas.example.ts.net:7600      up   100.0 GiB offered
  3         vps.example.ts.net:7600      down 100.0 GiB offered
scrub: idle
metadata log: 1 entries, 6720 objects
garbage collection: 0 chunks (0 bytes) pending, 0 chunks (0 bytes) reclaimed
STATUS
      ;;
    config)
      shift
      while [[ $# -gt 0 ]]; do
        case $1 in
          --offer) echo "$2" >"$DEMO_DIR/offer"; shift 2 ;;
          --copies) echo "$2" >"$DEMO_DIR/copies"; shift 2 ;;
          *) echo "startfs: unknown option $1" >&2; return 2 ;;
        esac
      done
      ;;
    *) echo "startfsgui: demo mode refuses to run 'startfs ${1:-}'" >&2; return 1 ;;
  esac
}

# ---- upgrading: nothing is run anywhere ---------------------------------------------------------
# Every node reports 1.0.6 until "updated" (the answer is kept in a file); the node called vps cannot be reached.
demo_version() { local f="$DEMO_DIR/versions/$1"; if [[ -f $f ]]; then cat "$f"; else echo "1.0.6 6"; fi; }
run_on() { # <host|""> <command>: answers the two commands lib/update.sh sends
  local host=${1:-self} cmd=$2 v
  [[ $host != vps ]] || { echo "ssh: connect to host vps port 22: Connection timed out" >&2; return 255; }
  mkdir -p "$DEMO_DIR/versions"
  case $cmd in
    *"startfs --version"*) read -r v p <<<"$(demo_version "$host")"; echo "startfs $v (protocol $p)" ;;
    *STARTFS_VERSION=*) v=${cmd#*STARTFS_VERSION=}; v=${v%% *}; v=${v#v}; demo_install "$host" "$v" ;;
    *) demo_install "$host" "1.0.7" ;;
  esac
}
demo_install() { # <host> <version>
  local cur; read -r cur _ <<<"$(demo_version "$1")"
  if [[ $cur == "$2" ]]; then echo "install: startfs $cur is already up to date"; return 0; fi
  echo "install: Downloading startfs-v$2-x86_64-linux"
  sleep 0.4; echo "install: Checksum verified"
  sleep 0.4; echo "install: Stopped startfs.service, replaced the binary (old one kept as startfs.prev)"
  sleep 0.4; echo "install: Started startfs.service; the daemon answers"
  echo "$2 6" >"$DEMO_DIR/versions/$1"
  echo "install: Upgraded startfs $cur to $2"
}
