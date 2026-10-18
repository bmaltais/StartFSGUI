# shellcheck shell=bash
# Upgrading a node is StartFS's own installer (scripts/install.sh in bmaltais/StartFS): it picks the release for the machine,
# verifies its checksum, swaps the binary (the old one stays as startfs.prev), restarts the daemon and rolls back if it does not
# answer. This file only runs it where the node is: here for this node, over ssh for another. StartFS has no built-in cluster
# update on purpose (.out-of-scope/built-in-update-command.md in its repo), and this is the loop that note recommends.

readonly INSTALL_URL="https://raw.githubusercontent.com/bmaltais/StartFS/main/scripts/install.sh"

# What reaches the shell of another machine is checked first, so a name cannot become an ssh option or a command.
valid_host() { [[ $1 =~ ^[A-Za-z0-9][A-Za-z0-9.-]{0,252}$ ]]; }
valid_version() { [[ $1 =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; }

# run_on <host|""> <sh command>: here when the host is empty, else over ssh. BatchMode so a missing key fails at once instead of
# waiting for a password nobody can type; the host name goes through ~/.ssh/config, so a User or Port set there applies.
run_on() {
  local host=$1 cmd=$2
  if [[ -z $host ]]; then sh -c "$cmd"
  else ssh -o BatchMode=yes -o ConnectTimeout=8 -- "$host" "$cmd"; fi
}

# update_args <args...>: sets UPD_HOST ("" for this node) and UPD_VERSION ("" for the latest release).
update_args() {
  UPD_HOST="" UPD_VERSION="" UPD_SELF=0 UPD_NAME=""
  while (($#)); do
    case $1 in
      --host) UPD_NAME=${2:-}; shift 2 ;;
      --self) UPD_SELF=1; shift ;;
      --version) UPD_VERSION=${2:-}; shift 2 ;;
      *) fail "unknown option $1" ;;
    esac
  done
  valid_host "$UPD_NAME" || fail "not a host name: '$UPD_NAME'"
  [[ -z $UPD_VERSION ]] || valid_version "$UPD_VERSION" || fail "not a release like v1.0.7: '$UPD_VERSION'"
  [[ $UPD_SELF == 1 ]] || UPD_HOST=$UPD_NAME
}

# version --host H [--self]: {ok, version, protocol} of the startfs installed there.
cmd_version() {
  update_args "$@"
  local out
  out=$(run_on "$UPD_HOST" 'PATH="$HOME/.local/bin:$PATH" startfs --version' 2>&1) || { reply_err "${out:-no answer}"; return 1; }
  if [[ $out =~ ^startfs\ ([0-9][^\ ]*)(\ \(protocol\ ([0-9]+)\))? ]]; then
    jq -nc --arg v "${BASH_REMATCH[1]}" --arg p "${BASH_REMATCH[3]:-0}" '{ok: true, version: $v, protocol: ($p | tonumber)}'
  else
    reply_err "unexpected answer: $out"; return 1
  fi
}

# update --host H [--self] [--version vX.Y.Z]: runs the installer there, its output line by line on stdout. Exit 0 when the
# node is current afterwards (including "already up to date").
cmd_update() {
  update_args "$@"
  local pin=""
  [[ -z $UPD_VERSION ]] || pin="STARTFS_VERSION=$UPD_VERSION "
  # Through a file, not a pipe into sh: a failed download must fail the update, and plain sh has no pipefail.
  run_on "$UPD_HOST" "f=\$(mktemp) && curl -fsSL '$INSTALL_URL' -o \"\$f\" && ${pin}sh \"\$f\"; rc=\$?; rm -f \"\$f\"; exit \$rc" 2>&1
}
