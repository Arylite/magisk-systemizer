# fs.sh - file helpers: byte compare, SELinux label, atomic swap, single-run lock.

# Run an Android service command (pm, dumpsys) and keep its output in a file. These
# commands make system_server write to the stdout they are given; it may write to a
# pipe, but not to a file under /data/adb (SELinux adb_data_file). So go through cat.
sz_capture() { # file command...
  cap_f=$1; shift
  "$@" 2>/dev/null | cat > "$cap_f"
}

# Byte comparison; cksum is the fallback where cmp does not exist.
sz_same() {
  if [ -n "$SZ_CMP" ]; then cmp -s "$1" "$2"
  else [ "$(cksum < "$1")" = "$(cksum < "$2")" ]; fi
}

# Set the SELinux label; a failure only matters when SELinux is enforcing.
sz_label() { # path... (recursive)
  [ -n "$SZ_CHCON" ] || return 0
  chcon -R "$SZ_CONTEXT" "$@" 2>/dev/null && return 0
  [ "$SZ_SELINUX" = Enforcing ] || return 0
  sz_err "chcon failed on $* while SELinux is enforcing"
  return 1
}

sz_ensure_dir() { # one directory level inside the overlay
  [ -d "$1" ] && return 0
  mkdir "$1" && chmod 755 "$1" || return 1
  [ -z "$SZ_CHCON" ] || chcon "$SZ_CONTEXT" "$1" 2>/dev/null || [ "$SZ_SELINUX" != Enforcing ]
}

# Rename new over target, keeping the old one aside until the rename worked.
sz_swap() { # new target
  sw_old=
  if [ -e "$2" ]; then
    mkdir -p "$SZ_WORK/trash" || return 1
    sw_old=$SZ_WORK/trash/old.$$.${2##*/}
    mv "$2" "$sw_old" || return 1
  fi
  mv "$1" "$2" && return 0
  [ -z "$sw_old" ] || mv "$sw_old" "$2"
  return 1
}

# One mutating command at a time; also clears what a killed run left behind.
sz_lock() {
  mkdir -p "$SZ_WORK" || sz_die "$SZ_FAIL" "cannot create $SZ_WORK"
  if ! mkdir "$SZ_WORK/lock" 2>/dev/null; then
    lk_pid=$(cat "$SZ_WORK/lock/pid" 2>/dev/null)
    if [ -n "$lk_pid" ] && kill -0 "$lk_pid" 2>/dev/null; then
      sz_die "$SZ_FAIL" "another systemizer command is running (pid $lk_pid)"
    fi
    sz_warn "removing a stale lock"
    rm -rf "$SZ_WORK/lock"
    mkdir "$SZ_WORK/lock" || sz_die "$SZ_FAIL" "cannot take the lock"
  fi
  printf '%s\n' "$$" > "$SZ_WORK/lock/pid"
  SZ_LOCKED=1
  for lk_d in "$SZ_WORK"/stage.* "$SZ_WORK"/trash; do
    [ -e "$lk_d" ] && sz_safe_rm "$lk_d"
  done
  for lk_d in "$SZ_WORK"/tmp.*; do # read-only commands take no lock: keep live ones
    [ -e "$lk_d" ] && ! kill -0 "${lk_d##*.}" 2>/dev/null && sz_safe_rm "$lk_d"
  done
  return 0
}
