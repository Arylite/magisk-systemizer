# discover.sh - find the APKs of a package and decide where they come from.

# pm path -> $SZ_TMP/paths (one APK per line), SZ_NPATHS, SZ_KIND:
# none | data (user install or update) | system | mixed | bad.
sz_installed_paths() {
  SZ_KIND=none SZ_NPATHS=0
  : > "$SZ_TMP/paths"
  sz_capture "$SZ_TMP/pm.out" pm path "$1"
  [ -s "$SZ_TMP/pm.out" ] || return 0
  ip_d=0 ip_s=0 ip_b=0
  while IFS= read -r ip_l; do
    case $ip_l in '') continue ;; package:/*.apk) ip_p=${ip_l#package:} ;; *) ip_b=$((ip_b + 1)); continue ;; esac
    case $ip_p in
      "$SZ_DATA"/*) ip_d=$((ip_d + 1)) ;;
      /system/*|/product/*|/vendor/*|/system_ext/*|/odm/*|/apex/*) ip_s=$((ip_s + 1)) ;;
      *) ip_b=$((ip_b + 1)); continue ;;
    esac
    printf '%s\n' "$ip_p" >> "$SZ_TMP/paths"
    SZ_NPATHS=$((SZ_NPATHS + 1))
  done < "$SZ_TMP/pm.out"
  if [ $ip_b -gt 0 ]; then SZ_KIND=bad
  elif [ $ip_d -gt 0 ] && [ $ip_s -gt 0 ]; then SZ_KIND=mixed
  elif [ $ip_d -gt 0 ]; then SZ_KIND=data
  elif [ $ip_s -gt 0 ]; then SZ_KIND=system
  fi
}

sz_user_packages() { # -> $SZ_TMP/pk.list, sorted when sort exists
  sz_capture "$SZ_TMP/pk.raw" pm list packages -3
  : > "$SZ_TMP/pk.unsorted"
  while IFS= read -r up_l; do
    up_n=${up_l#package:}
    sz_valid_pkg "$up_n" && printf '%s\n' "$up_n" >> "$SZ_TMP/pk.unsorted"
  done < "$SZ_TMP/pk.raw"
  if sz_have sort; then sort "$SZ_TMP/pk.unsorted" > "$SZ_TMP/pk.list"; else cp "$SZ_TMP/pk.unsorted" "$SZ_TMP/pk.list"; fi
}

sz_apk_pkgname() { # apk -> the package name, or status 1
  [ -n "$SZ_AAPT" ] || return 1
  an_n=
  if [ "$SZ_AAPT_KIND" = aapt2 ]; then
    "$SZ_AAPT" dump packagename "$1" > "$SZ_TMP/aapt.out" 2>/dev/null || return 1
    IFS= read -r an_n < "$SZ_TMP/aapt.out"
  else
    "$SZ_AAPT" dump badging "$1" > "$SZ_TMP/aapt.out" 2>/dev/null || return 1
    while IFS= read -r an_l; do
      case $an_l in "package: name='"*) an_n=${an_l#"package: name='"}; an_n=${an_n%%\'*}; break ;; esac
    done < "$SZ_TMP/aapt.out"
  fi
  sz_valid_pkg "$an_n" || return 1
  printf '%s\n' "$an_n"
}

# Identity of an --apk file. Sets in_name; dies unless the file is provably the
# package it claims to be. An installed package is only matched byte for byte.
sz_resolve_apk() {
  rs_apkname=
  case $in_apk in /*) ;; *) in_apk=$PWD/$in_apk ;; esac
  [ -f "$in_apk" ] && [ -r "$in_apk" ] || sz_die "$SZ_NOTFOUND" "APK not readable: $in_apk"
  case $in_apk in *.apk) ;; *) sz_die "$SZ_USAGE" "not an .apk file: $in_apk" ;; esac
  if rs_apkname=$(sz_apk_pkgname "$in_apk"); then
    if [ -n "$in_name" ] && [ "$in_name" != "$rs_apkname" ]; then
      sz_die "$SZ_VERIFY" "the APK is package $rs_apkname, not $in_name"
    fi
    in_name=$rs_apkname
  elif [ -z "$in_name" ]; then
    sz_die "$SZ_UNSUPPORTED" "cannot read the package name of $in_apk: no aapt/aapt2 found (put one in $SZ_MODDIR/bin or on PATH), or pass --package NAME for an app that is already installed"
  fi
}

# Decide where the APKs come from. Sets in_name, SZ_SRC (installed|file) and
# leaves SZ_KIND / SZ_NPATHS / $SZ_TMP/paths describing the sources.
sz_resolve_sources() {
  rs_apkname=
  [ -z "$in_apk" ] || sz_resolve_apk
  sz_valid_pkg "$in_name" || sz_die "$SZ_USAGE" "invalid package name: $in_name"
  sz_installed_paths "$in_name"
  case $SZ_KIND in
    mixed|bad) sz_die "$SZ_VERIFY" "pm reports unexpected APK locations for $in_name; refusing to guess" ;;
  esac
  SZ_SRC=installed
  if [ -n "$in_apk" ]; then
    case $SZ_KIND in
      data|system)
        [ "$SZ_NPATHS" -eq 1 ] || sz_die "$SZ_VERIFY" "$in_name is installed as $SZ_NPATHS split APKs; --apk cannot represent it, use the package name"
        IFS= read -r rs_inst < "$SZ_TMP/paths"
        sz_same "$in_apk" "$rs_inst" || sz_die "$SZ_VERIFY" "$in_apk differs from the installed APK of $in_name. A different build cannot be checked for signature compatibility: update the app normally (pm install -r), then use the package name"
        ;;
      none)
        [ -n "$rs_apkname" ] || sz_die "$SZ_UNSUPPORTED" "$in_name is not installed, so the APK identity cannot be checked without aapt/aapt2"
        printf '%s\n' "$in_apk" > "$SZ_TMP/paths"; SZ_NPATHS=1; SZ_SRC="file" ;;
    esac
  elif [ "$SZ_KIND" = none ]; then
    sz_die "$SZ_NOTFOUND" "package not installed: $in_name"
  fi
  if [ "$SZ_KIND" = data ] || [ "$SZ_SRC" = file ]; then
    while IFS= read -r rs_p; do
      [ -f "$rs_p" ] && [ -r "$rs_p" ] || sz_die "$SZ_VERIFY" "APK missing or unreadable: $rs_p"
    done < "$SZ_TMP/paths"
  fi
}
