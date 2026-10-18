# shellcheck shell=bash
# Shared by every command: talking to the real `startfs`, and checking what is typed before it gets there.

# The size grammar of `startfs config --offer`: a number with an optional K, M, G or T (and an optional iB), or 0.
valid_size() { [[ $1 =~ ^([0-9]+|[0-9]+(\.[0-9]+)?[KMGT]i?B?)$ ]]; }
valid_copies() { [[ $1 =~ ^[1-9]$ ]]; }

# Lines of JSON on stdout, so the QML can tell a refusal from a crash: {ok:true} or {ok:false, error}.
reply_ok() { printf '{"ok":true}\n'; }
reply_err() { jq -nc --arg e "$1" '{ok: false, error: $e}'; return 1; }

cmd_status() { startfs status; }

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
