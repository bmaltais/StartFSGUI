# shellcheck shell=bash
# Shared by every command: talking to the real `startfs`, and checking what is typed before it gets there.

# The size grammar of `startfs config --offer`: a number with an optional K, M, G or T (and an optional iB), or 0.
valid_size() { [[ $1 =~ ^([0-9]+|[0-9]+(\.[0-9]+)?[KMGT]i?B?)$ ]]; }
valid_copies() { [[ $1 =~ ^[1-9]$ ]]; }

fail() {
  echo "startfsgui: $*" >&2
  exit 1
}

# write_file <dest> <mode>: content on stdin, written to a temporary file beside the destination and renamed into place, so a
# half-written file is never seen and a link planted at the destination is replaced rather than written through.
write_file() {
  local dest=$1 mode=$2 dir tmp
  dir=$(dirname "$dest")
  mkdir -p -- "$dir"
  tmp=$(mktemp "$dir/.$(basename "$dest").XXXXXX") || fail "cannot create a temporary file in $dir"
  if ! cat >"$tmp" || ! chmod "$mode" "$tmp" || ! mv -T -f "$tmp" "$dest"; then
    rm -f "$tmp"
    fail "cannot write $dest"
  fi
}

# Lines of JSON on stdout, so the QML can tell a refusal from a crash: {ok:true} or {ok:false, error}.
reply_ok() { printf '{"ok":true}\n'; }
reply_err() { jq -nc --arg e "$1" '{ok: false, error: $e}'; return 1; }

# Builds that have `--json` give the plugin everything; an older one is read from its text (see StartFSModel.js).
cmd_status() { startfs status --json 2>/dev/null || startfs status; }

# Every member's storage figures, right now (`startfs stats`, which builds after 1.0.7 have). An older startfs fails here and the
# window simply shows no per-node figures.
cmd_stats() { startfs stats --json; }

cmd_set() {
  local key=${1:-} value=${2:-} out
  case $key in
    offer)
      valid_size "$value" || { reply_err "Not a size: '$value'. Use a number with K, M, G or T, like 500G."; return 1; }
      out=$(startfs config --offer "$value" 2>&1) || { reply_err "$out"; return 1; }
      ;;
    copies)
      valid_copies "$value" || { reply_err "Copies must be a number from 1 to 9."; return 1; }
      out=$(startfs config --copies "$value" 2>&1) || { reply_err "$out"; return 1; }
      ;;
    *) reply_err "Unknown setting '$key' (offer | copies)"; return 1 ;;
  esac
  reply_ok
}
