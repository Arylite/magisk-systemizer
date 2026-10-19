# xml.sh - privapp-permissions allowlist: generate it, and check what was generated.

sz_gen_xml() { # pkg grantfile denyfile outfile
  {
    printf '<?xml version="1.0" encoding="utf-8"?>\n<permissions>\n'
    printf '    <privapp-permissions package="%s">\n' "$1"
    while IFS= read -r gx_p; do
      [ -n "$gx_p" ] && printf '        <permission name="%s"/>\n' "$gx_p"
    done < "$2"
    while IFS= read -r gx_p; do
      [ -n "$gx_p" ] && printf '        <deny-permission name="%s"/>\n' "$gx_p"
    done < "$3"
    printf '    </privapp-permissions>\n</permissions>\n'
  } > "$4"
}

# Accept only the exact shape sz_gen_xml writes, with at least one entry.
sz_xml_ok() { # file pkg
  sx_n=0 sx_e=0 sx_last=
  while IFS= read -r sx_l; do
    sx_n=$((sx_n + 1)); sx_last=$sx_l
    case $sx_l in
      '<?xml version="1.0" encoding="utf-8"?>') [ $sx_n -eq 1 ] || return 1 ;;
      '<permissions>') [ $sx_n -eq 2 ] || return 1 ;;
      "    <privapp-permissions package=\"$2\">") [ $sx_n -eq 3 ] || return 1 ;;
      '    </privapp-permissions>'|'</permissions>') ;;
      '        <permission name="'*'"/>'|'        <deny-permission name="'*'"/>')
        sx_x=${sx_l#*name=\"}; sx_x=${sx_x%\"/>}
        sz_valid_perm "$sx_x" || return 1
        sx_e=$((sx_e + 1)) ;;
      *) return 1 ;;
    esac
  done < "$1"
  [ $sx_e -ge 1 ] && [ "$sx_last" = '</permissions>' ]
}
