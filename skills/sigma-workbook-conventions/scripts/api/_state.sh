#!/usr/bin/env bash
# Shared credential/state persistence for the browser-login flow.
#
# Sourced by scripts/api/browser-login.sh and scripts/api/refresh-token.sh.
# Not executable on its own.
#
# Three storage tiers, in preference order:
#   1. macOS keychain      (`security`)
#   2. Linux libsecret     (`secret-tool`)
#   3. A 0600 file under $SIGMA_STATE_DIR   <-- the Cowork/sandbox tier
#
# Tier 3 exists because a Claude Cowork session runs shell commands in an
# isolated environment on Anthropic's servers: there is no OS keychain there,
# and environment variables do not survive between separate bash tool calls.
# Without a persisted refresh token, EVERY subsequent scripts/api/*.sh call
# would demand a fresh browser sign-in. See reference/workflows/cowork.md.
#
# SECURITY -- tier 3 must never write inside the workspace. A Cowork folder is
# synced back to the user's real disk, and CLAUDE.md forbids secrets in
# workspace files. state_dir() hard-refuses a $SIGMA_STATE_DIR that resolves
# inside the skill root or the enclosing git repo, rather than silently
# writing a credential somewhere that gets committed or synced.

# Resolve the skill root (…/skills/sigma-workbook-conventions) from this file's
# own location, so the guard below works regardless of the caller's cwd.
_state_skill_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd
}

# Absolute path without requiring the directory to exist yet (realpath -m and
# readlink -f are not portable across macOS/Linux/Git Bash).
_state_abspath() {
  local p="$1" dir base
  dir=$(dirname "$p"); base=$(basename "$p")
  if [ -d "$p" ]; then (cd "$p" && pwd)
  elif [ -d "$dir" ]; then printf '%s/%s\n' "$(cd "$dir" && pwd)" "$base"
  else printf '%s\n' "$p"
  fi
}

# Print the state directory, creating it 0700 on first use.
# Override with SIGMA_STATE_DIR; defaults to an XDG-ish per-user path.
state_dir() {
  local dir resolved root repo
  dir="${SIGMA_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/sigma-workbook-skill}"
  resolved=$(_state_abspath "$dir")

  # --- Guard: never persist a secret inside the workspace. ---
  root=$(_state_skill_root)
  case "$resolved/" in
    "$root"/*)
      echo "Error: refusing to write credentials inside the skill directory ($resolved)." >&2
      echo "       A Cowork workspace syncs back to your disk; secrets must not live there." >&2
      echo "       Unset SIGMA_STATE_DIR, or point it outside the repo." >&2
      return 1 ;;
  esac
  if repo=$(git -C "$root" rev-parse --show-toplevel 2>/dev/null) && [ -n "$repo" ]; then
    repo=$(_state_abspath "$repo")
    case "$resolved/" in
      "$repo"/*)
        echo "Error: refusing to write credentials inside the git repo ($resolved)." >&2
        echo "       Secrets must not be committable. Point SIGMA_STATE_DIR outside the repo." >&2
        return 1 ;;
    esac
  fi

  mkdir -p "$resolved" 2>/dev/null || { echo "Error: could not create state dir $resolved" >&2; return 1; }
  chmod 700 "$resolved" 2>/dev/null || true
  printf '%s\n' "$resolved"
}

# Write $2 to the state file named $1, 0600, created atomically-ish.
state_write() { # state_write <name> <value>
  local dir file
  dir=$(state_dir) || return 1
  file="$dir/$1"
  ( umask 077; printf '%s' "$2" >"$file" ) || return 1
  chmod 600 "$file" 2>/dev/null || true
}

state_read() { # state_read <name>
  local dir file
  dir=$(state_dir 2>/dev/null) || return 0
  file="$dir/$1"
  [ -f "$file" ] && cat "$file" 2>/dev/null || true
}

state_clear() { # state_clear <name>
  local dir
  dir=$(state_dir 2>/dev/null) || return 0
  rm -f "$dir/$1" 2>/dev/null || true
}

# --- Unified three-tier accessors -------------------------------------------
# cred_get/cred_set hide which tier is in play so callers stay identical
# across macOS, Linux, and a Cowork sandbox.

if command -v security >/dev/null 2>&1; then
  SIGMA_CRED_TIER=macos
elif command -v secret-tool >/dev/null 2>&1; then
  SIGMA_CRED_TIER=libsecret
else
  SIGMA_CRED_TIER=file
fi

cred_get() { # cred_get <name>
  case "$SIGMA_CRED_TIER" in
    macos)     security find-generic-password -a "$USER" -s "sigma-api:$1" -w 2>/dev/null || true ;;
    libsecret) secret-tool lookup service sigma-api key "$1" 2>/dev/null || true ;;
    file)      state_read "cred-$1" ;;
  esac
}

cred_set() { # cred_set <name> <value>
  case "$SIGMA_CRED_TIER" in
    macos)     security add-generic-password -U -a "$USER" -s "sigma-api:$1" -w "$2" >/dev/null 2>&1 || return 1 ;;
    libsecret) printf '%s' "$2" | secret-tool store --label="sigma-api $1" service sigma-api key "$1" >/dev/null 2>&1 || return 1 ;;
    file)      state_write "cred-$1" "$2" || return 1 ;;
  esac
}

# Human-readable name for the active tier, for log lines.
cred_tier_label() {
  case "$SIGMA_CRED_TIER" in
    macos)     printf 'macOS keychain' ;;
    libsecret) printf 'libsecret' ;;
    file)      printf '0600 file under %s' "$(state_dir 2>/dev/null || printf '<unavailable>')" ;;
  esac
}

# True when there is no way to prompt a human on this host: no tty on stdin and
# no controlling terminal. This is exactly the Cowork bash-tool case, and it is
# why browser-login.sh cannot block on `read` there.
is_headless() {
  [ -t 0 ] && return 1
  (exec 3</dev/tty) 2>/dev/null && { exec 3<&- 2>/dev/null; return 1; }
  return 0
}
