# shellcheck shell=bash
# Shared by every command: talking to the real `startfs`, and checking what is typed before it gets there.

# The size grammar of `startfs config --offer` and `--weight`: an integer (no decimals) with an optional unit B, K, KB, KiB, M, MB,
# MiB, G, GB, GiB, T, TB or TiB in any case. 0 is a size too (a pure client for --offer, "follow the offer" for --weight).
valid_size() { local s=${1^^}; [[ $s =~ ^[0-9]{1,15}(B|[KMGT](I?B)?)?$ ]]; }
valid_copies() { [[ $1 =~ ^[1-9]$ ]]; }
valid_site() { [[ $1 =~ ^[A-Za-z0-9._-]{0,64}$ ]]; }
valid_member() { [[ $1 =~ ^[0-9]{1,10}$ ]]; }

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
reply_msg() { jq -nc --arg m "$1" '{ok: true, message: $m}'; }

# run_startfs <command...>: runs it, keeps stdout in SF_OUT and stderr in SF_ERR (startfs's "startfs: " prefix dropped, lines
# joined) and returns its exit status, so an error can be handed to the UI in startfs's own words.
run_startfs() {
  local errf rc=0
  errf=$(mktemp) || fail "cannot create a temporary file"
  SF_OUT=$("$@" 2>"$errf") || rc=$?
  SF_ERR=$(sed 's/^startfs: //' "$errf" | paste -sd' ')
  rm -f "$errf"
  return "$rc"
}

# Builds that have `--json` give the plugin everything; an older one is read from its text (see StartFSModel.js).
cmd_status() { startfs status --json 2>/dev/null || startfs status; }

# Every member's storage figures, right now (`startfs stats`, which builds after 1.0.7 have). An older startfs fails here and the
# window simply shows no per-node figures.
cmd_stats() { startfs stats --json; }

# This node's last minute of traffic, tick timings and queues (`startfs activity`, 1.4.0 and later).
cmd_activity() { startfs activity --json; }

# ---- the newest release -------------------------------------------------------------------------
readonly LATEST_URL="https://api.github.com/repos/bmaltais/StartFS/releases/latest"
readonly LATEST_TTL=21600

# The cache lives with the user's other caches; demo mode moves it so a screenshot run never writes there.
latest_cache_file() { printf '%s' "${XDG_CACHE_HOME:-$HOME/.cache}/startfsgui/latest.json"; }
# The tag of the newest stable release, from GitHub. Its own function so a test or demo can stand in for the network.
latest_fetch() { curl -fsSL --max-time 8 -H 'Accept: application/vnd.github+json' "$LATEST_URL" | jq -er .tag_name; }

# latest [--refresh]: {ok, release}. GitHub is asked at most every six hours (it limits anonymous callers); a failed ask falls
# back to an older answer, because "the newest release we last heard of" beats saying nothing while offline.
cmd_latest() {
  local refresh=0 file now tag="" cached="" fetched=0
  case ${1:-} in
    "") ;;
    --refresh) refresh=1 ;;
    *) reply_err "unknown option ${1}"; return 1 ;;
  esac
  file=$(latest_cache_file) now=$(date +%s)
  if [[ -f $file ]]; then
    cached=$(jq -r '.release // empty' "$file" 2>/dev/null || true)
    fetched=$(jq -r '.fetched_at // 0' "$file" 2>/dev/null || echo 0)
    valid_version "$cached" || cached=""
    [[ $fetched =~ ^[0-9]+$ ]] || fetched=0
  fi
  if [[ $refresh == 0 && -n $cached ]] && ((now - fetched >= 0 && now - fetched < LATEST_TTL)); then
    jq -nc --arg r "$cached" '{ok: true, release: $r}'
    return 0
  fi
  tag=$(latest_fetch 2>/dev/null) || tag=""
  if valid_version "$tag"; then
    # A cache that cannot be written costs only the next lookup.
    (jq -nc --arg r "$tag" --argjson t "$now" '{release: $r, fetched_at: $t}' | write_file "$file" 644) 2>/dev/null || true
    jq -nc --arg r "$tag" '{ok: true, release: $r}'
  elif [[ -n $cached ]]; then
    jq -nc --arg r "$cached" '{ok: true, release: $r}'
  else
    reply_err "Could not look up the newest release (no answer from GitHub)."
  fi
}

# ---- settings -----------------------------------------------------------------------------------
# set KEY VALUE [--host H]: one `startfs config` flag, here or (offer, weight, site only) on another node over ssh.
# Prints {ok:true}, {ok:true, warning} when startfs succeeded but said something, or {ok:false, error}.
cmd_set() {
  local key=${1:-} value host=""
  case $key in
    offer | weight | site | copies | activity) ;;
    *) reply_err "Unknown setting '$key' (offer | weight | site | copies | activity)"; return 1 ;;
  esac
  (($# >= 2)) || { reply_err "Setting $key needs a value."; return 1; }
  value=$2
  shift 2
  while (($#)); do
    case $1 in
      --host) host=${2:-}; shift 2 || shift ;;
      *) reply_err "unknown option $1"; return 1 ;;
    esac
  done
  case $key in
    offer | weight) valid_size "$value" || { reply_err "Not a size: '$value'. Use a whole number with K, M, G or T, like 500G."; return 1; } ;;
    site) valid_site "$value" || { reply_err "A site name is up to 64 letters, digits, dots, dashes and underscores."; return 1; } ;;
    copies) valid_copies "$value" || { reply_err "Copies must be a number from 1 to 9."; return 1; } ;;
    activity) [[ $value == on || $value == off ]] || { reply_err "Activity is on or off."; return 1; } ;;
  esac
  if [[ -n ${host:-} ]]; then
    valid_host "$host" || { reply_err "Not a host name: '$host'"; return 1; }
    [[ $key == offer || $key == weight || $key == site ]] || { reply_err "$key is set on the node itself, not on another one."; return 1; }
    # The value is checked above to hold only plain characters, so single quotes are all the shell there needs.
    run_startfs run_on "$host" "PATH=\"\$HOME/.local/bin:\$PATH\" startfs config --$key '$value'" || { reply_err "${SF_ERR:-no answer from $host}"; return 1; }
  else
    run_startfs startfs config "--$key" "$value" || { reply_err "${SF_ERR:-startfs failed}"; return 1; }
  fi
  if [[ -n $SF_ERR ]]; then jq -nc --arg w "${SF_ERR#warning: }" '{ok: true, warning: $w}'; else reply_ok; fi
}

# ---- cluster actions ----------------------------------------------------------------------------
# upgrade [vX.Y.Z] [--force]: the whole cluster moves to a release (the newest unless named). It returns at once; the members stage
# the release and restart one by one, and `status` shows how far they are. --force restarts this node although its mount is in use.
cmd_upgrade() {
  local tag="" force=()
  while (($#)); do
    case $1 in
      --force) force=(--force); shift ;;
      -*) reply_err "unknown option $1"; return 1 ;;
      *) valid_version "$1" || { reply_err "Not a release like v1.10.3: '$1'"; return 1; }; tag=$1; shift ;;
    esac
  done
  run_startfs startfs update ${tag:+"$tag"} "${force[@]}" || { reply_err "${SF_ERR:-startfs failed}"; return 1; }
  reply_msg "$SF_OUT"
}

# remove N: drops a member that is gone for good (startfs refuses while it is still online).
cmd_remove() {
  valid_member "${1:-}" || { reply_err "Remove needs a member number."; return 1; }
  run_startfs startfs remove "$1" || { reply_err "${SF_ERR:-startfs failed}"; return 1; }
  reply_ok
}

# leave: this node hands its data to the others and leaves. It returns at once; the handover goes on in the background.
cmd_leave() {
  run_startfs startfs leave || { reply_err "${SF_ERR:-startfs failed}"; return 1; }
  reply_msg "$SF_OUT"
}

# purge: every member frees the data of deleted files now instead of after the retention period. Not undoable.
cmd_purge() {
  run_startfs startfs purge || { reply_err "${SF_ERR:-startfs failed}"; return 1; }
  reply_msg "$SF_OUT"
}

# Puts text on the clipboard; false when there is no wl-copy. Its own function so demo mode can leave the real clipboard alone.
clipboard_copy() { command -v wl-copy >/dev/null && printf '%s' "$1" | wl-copy; }

# invite [--copy]: {ok, command} where command is what the other machine runs to join; --copy also copies it and adds copied.
cmd_invite() {
  local copy=0 cmd
  case ${1:-} in
    "") ;;
    --copy) copy=1 ;;
    *) reply_err "unknown option ${1}"; return 1 ;;
  esac
  run_startfs startfs token --example || { reply_err "${SF_ERR:-startfs failed}"; return 1; }
  cmd=$SF_OUT
  [[ $cmd == "startfs join "* ]] || { reply_err "unexpected answer: $cmd"; return 1; }
  if [[ $copy == 1 ]]; then
    if clipboard_copy "$cmd" 2>/dev/null; then
      jq -nc --arg c "$cmd" '{ok: true, command: $c, copied: true}'
    else
      jq -nc --arg c "$cmd" '{ok: true, command: $c, copied: false}'
    fi
  else
    jq -nc --arg c "$cmd" '{ok: true, command: $c}'
  fi
}

# ---- the daemon's log ---------------------------------------------------------------------------
# The log is the journal of the user unit (there is no log file). Its own function so demo mode can show a stand-in.
logs_command() { printf '%s' 'journalctl --user -u startfs -f -n 200'; }

# logs: opens the log in a terminal of its own, detached so closing the manager does not close it. The terminal is the user's
# default one (xdg-terminal-exec), else $TERMINAL, else foot or alacritty.
cmd_logs() {
  local cmd
  cmd=$(logs_command)
  if command -v xdg-terminal-exec >/dev/null; then
    setsid -f xdg-terminal-exec --app-id=startfsgui-logs -- sh -c "$cmd" >/dev/null 2>&1
  elif [[ -n ${TERMINAL:-} ]] && command -v "$TERMINAL" >/dev/null; then
    setsid -f "$TERMINAL" -e sh -c "$cmd" >/dev/null 2>&1
  elif command -v foot >/dev/null; then
    setsid -f foot --app-id=startfsgui-logs sh -c "$cmd" >/dev/null 2>&1
  elif command -v alacritty >/dev/null; then
    setsid -f alacritty --class startfsgui-logs -e sh -c "$cmd" >/dev/null 2>&1
  else
    reply_err "No terminal found to show the log in (set TERMINAL, or install foot or alacritty)."; return 1
  fi
  reply_ok
}
