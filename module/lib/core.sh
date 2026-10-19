# core.sh - constants, output helpers, validation, overlay paths.
# Portable sh (mksh, ash, dash, bash). No "local", arrays, [[ ]] or here-documents:
# Android's mksh has no "local" and needs a writable TMPDIR for here-documents.
# Functions return a status; only sz_die exits. Never call sz_die inside $( ).

SZ_OK=0; SZ_FAIL=1; SZ_USAGE=2; SZ_NOTFOUND=3; SZ_UNSUPPORTED=4
SZ_VERIFY=5; SZ_STALE=6; SZ_REFUSED=7
SZ_CONTEXT=u:object_r:system_file:s0

sz_say()  { printf '%s\n' "$*"; }
sz_warn() { printf 'warning: %s\n' "$*" >&2; }
sz_err()  { printf 'error: %s\n' "$*" >&2; }
sz_die()  { sz_die_rc=$1; shift; sz_err "$*"; exit "$sz_die_rc"; }
sz_have() { command -v "$1" >/dev/null 2>&1; }
sz_usage_die() { sz_err "$*"; printf 'Try: systemizer help\n' >&2; exit "$SZ_USAGE"; }

# ---- validation ---------------------------------------------------------------

# Java-style dotted name with at least two segments, each starting with a letter.
sz_valid_pkg() {
  case $1 in ''|*[!A-Za-z0-9._]*) return 1 ;; esac
  [ "${#1}" -le 255 ] || return 1
  printf '%s\n' "$1" | grep -Eq '^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$'
}

sz_valid_perm() {
  case $1 in ''|*[!A-Za-z0-9._]*) return 1 ;; esac
  [ "${#1}" -le 255 ] || return 1
  printf '%s\n' "$1" | grep -Eq '^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$'
}

# ---- paths of one managed package (sets globals; no subshell) -------------------

sz_paths() {
  SZ_P_APP=$SZ_OVL/app/$1
  SZ_P_PRIV=$SZ_OVL/priv-app/$1
  SZ_P_XML=$SZ_OVL/etc/permissions/privapp-permissions-$1.xml
  SZ_P_STATE=$SZ_STATE/$1.conf
}

# Overlay directory for a mode: sets SZ_P_SUB (app|priv-app) and SZ_P_DIR.
sz_modedir() { # pkg mode
  sz_paths "$1"
  if [ "$2" = privileged ]; then SZ_P_SUB=priv-app; SZ_P_DIR=$SZ_P_PRIV
  else SZ_P_SUB=app; SZ_P_DIR=$SZ_P_APP; fi
}

# Delete only what this module owns: its work dir, overlay entries, state files.
sz_safe_rm() {
  for sr_p in "$@"; do
    case $sr_p in *..*) sz_err "internal: refusing to delete $sr_p"; return 1 ;; esac
    case $sr_p in
      "$SZ_WORK"/?*|"$SZ_OVL"/app/?*|"$SZ_OVL"/priv-app/?*) ;;
      "$SZ_OVL"/etc/permissions/privapp-permissions-?*.xml|"$SZ_STATE"/?*.conf) ;;
      *) sz_err "internal: refusing to delete $sr_p"; return 1 ;;
    esac
    rm -rf "$sr_p" || return 1
  done
}
