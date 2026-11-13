#!/usr/bin/env bash
set -euo pipefail

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
gtk_css="$config_dir/gtk-3.0/gtk.css"
import_line='@import url("umbriel-buttons.css");'

mkdir -p "$(dirname "$gtk_css")"
touch "$gtk_css"

if grep -qxF "$import_line" "$gtk_css"; then
    exit 0
fi

tmp="$(mktemp "${gtk_css}.tmp.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

awk -v imp="$import_line" '
    BEGIN { inserted = 0 }
    {
        line = $0
        if (!inserted &&
            line !~ /^[[:space:]]*$/ &&
            line !~ /^[[:space:]]*\/\*/ &&
            line !~ /^[[:space:]]*\*/ &&
            line !~ /^[[:space:]]*@import/) {
            print imp
            inserted = 1
        }
        print line
    }
    END { if (!inserted) print imp }
' "$gtk_css" >"$tmp"

cat "$tmp" >"$gtk_css"

# Ask GTK to re-read its user stylesheet so running apps pick up the new colors.
touch "$gtk_css" 2>/dev/null || true
