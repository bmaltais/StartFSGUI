# shellcheck shell=bash
# Demo mode: a fixture cluster and no contact with the real daemon. Loaded by bin/startfsgui only when STARTFSGUI_DEMO=1 or
# $CONFIG_DIR/demo/ENABLED exists. The test session shares your user, so without this a click there would reconfigure the live
# cluster. `startfs` is shadowed by a function: status is answered from the fixture below, `config` is recorded in a file.

readonly DEMO_DIR="$CONFIG_DIR/demo"
mkdir -p "$DEMO_DIR"
[[ -f $DEMO_DIR/offer ]] || echo "10.0 GiB" >"$DEMO_DIR/offer"
[[ -f $DEMO_DIR/copies ]] || echo 3 >"$DEMO_DIR/copies"

startfs() {
  case ${1:-} in
    status)
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
