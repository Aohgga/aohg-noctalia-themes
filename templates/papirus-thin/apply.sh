#!/usr/bin/env bash
# papirus-thin — 为 Papirus 建薄覆盖层：只建目录骨架和 folder 链接，不复制整个主题。
# 文件夹颜色跟随 Noctalia 渲染出的 colors-final。
set -euo pipefail

CONFIG_DIR="$(cd "$(dirname "$0")" && pwd)"
COLOR_FILE="$CONFIG_DIR/colors-final"
[[ -f "$COLOR_FILE" ]] || exit 0

mapfile -t lines <"$COLOR_FILE"
TARGET="${lines[0]//[# ]/}"
[[ ${#TARGET} -ge 6 ]] || exit 0
TARGET="${TARGET:0:6}"

MAPPING="$(printf '%s\n' "${lines[@]}" | sed '/^[[:space:]]*$/d' | tail -n1)"

# surface 亮度 -> 用 Papirus-Dark 还是 Papirus-Light
SURFACE="${lines[1]//[# ]/}"
LUMA=0
if [[ ${#SURFACE} -ge 6 ]]; then
  SURFACE="${SURFACE:0:6}"
  SR=$((16#${SURFACE:0:2}))
  SG=$((16#${SURFACE:2:2}))
  SB=$((16#${SURFACE:4:2}))
  LUMA=$(((SR * 299 + SG * 587 + SB * 114) / 1000))
fi
ACTIVE="Papirus-Dark"
((LUMA >= 128)) && ACTIVE="Papirus-Light"

# HSV 最近色，和上游 papirus-icons 模板一致
closest="$(
  awk -v r="${TARGET:0:2}" -v g="${TARGET:2:2}" -v b="${TARGET:4:2}" -v m="$MAPPING" '
  function hex2dec(h,   i,c,v,digits) {
    digits = "0123456789abcdef"; h = tolower(h); v = 0
    for (i=1; i<=length(h); i++) v = v*16 + (index(digits, substr(h,i,1)) - 1)
    return v
  }
  function rgb2hsv(r,g,b,   mx,mn,d,h,s,v,t) {
    r/=255; g/=255; b/=255
    mx=(r>g)?(r>b?r:b):(g>b?g:b); mn=(r<g)?(r<b?r:b):(g<b?g:b)
    v=mx; d=mx-mn
    if (d==0) { s=0; h=0 }
    else {
      s=d/mx
      if (mx==r) { t=(g-b)/d; if(t<0) t+=6; h=60*t }
      else if (mx==g) { h=60*(((b-r)/d)+2) }
      else { h=60*(((r-g)/d)+4) }
    }
    return h SUBSEP s SUBSEP v
  }
  BEGIN {
    WH=10; WS=1; WV=0.3
    split(rgb2hsv(hex2dec(r),hex2dec(g),hex2dec(b)), tgt, SUBSEP)
    th=tgt[1]+0; ts=tgt[2]+0; tv=tgt[3]+0
    n=split(m, arr)
    for (i=1; i<=n; i++) {
      split(arr[i], p, ":")
      split(rgb2hsv(hex2dec(substr(p[2],1,2)),hex2dec(substr(p[2],3,2)),hex2dec(substr(p[2],5,2))), c, SUBSEP)
      ch=c[1]+0; cs=c[2]+0; cv=c[3]+0
      dh=th-ch; if(dh<0) dh=-dh; if(dh>180) dh=360-dh; dh/=180
      ds=ts-cs; dv=tv-cv
      d=WH*(ts*cs)*dh*dh + WS*ds*ds + WV*dv*dv
      if (min=="" || d<min) { min=d; best=p[1] }
    }
    print best
  }'
)"
[[ -n "$closest" ]] || { echo "papirus-thin: 没有匹配的颜色" >&2; exit 0; }

colors=()
for pair in $MAPPING; do colors+=("${pair%%:*}"); done

# 找系统 Papirus：XDG_DATA_DIRS（NixOS 上是 /etc/profiles/per-user/$USER/share 等）
dirs=()
IFS=: read -ra dirs <<<"${XDG_DATA_DIRS:-}"
dirs+=(/usr/local/share /usr/share)

find_src() {
  local v=$1 d
  for d in "${dirs[@]}"; do
    [[ -n "$d" && -d "$d/icons/$v" ]] || continue
    readlink -f "$d/icons/$v"
    return 0
  done
  return 1
}

# folder-<颜色>.svg / folder-<颜色>-x.svg / user-<颜色>-x.svg 这类是颜色变体
is_color_variant() {
  local base=$1 c
  for c in "${colors[@]}"; do
    [[ "$base" == "folder-$c" || "$base" == folder-"$c"-* ]] && return 0
    [[ "$base" == "user-$c" || "$base" == user-"$c"-* ]] && return 0
  done
  return 1
}

build_places() {
  local src=$1 dest=$2 entry name base cand
  mkdir -p "$dest"
  for entry in "$src"/*.svg; do
    [[ -e "$entry" || -L "$entry" ]] || continue
    name="${entry##*/}"
    base="${name%.svg}"
    is_color_variant "$base" && continue
    cand=""
    case "$base" in
      folder) cand="$src/folder-$closest.svg" ;;
      folder-*) cand="$src/folder-$closest-${base#folder-}.svg" ;;
      user) cand="$src/user-$closest.svg" ;;
      user-*) cand="$src/user-$closest-${base#user-}.svg" ;;
    esac
    if [[ -n "$cand" && -e "$cand" ]]; then
      ln -sfn "$(readlink -f "$cand")" "$dest/$name"
    else
      ln -sfn "$(readlink -f "$entry")" "$dest/$name"
    fi
  done
}

SIZES="22x22 24x24 32x32 48x48 64x64"

build_size() {
  local src=$1 dest=$2 entry name
  mkdir -p "$dest"
  for entry in "$src"/*; do
    [[ -e "$entry" || -L "$entry" ]] || continue
    name="${entry##*/}"
    if [[ "$name" == places ]]; then
      build_places "$src/places" "$dest/places"
    else
      ln -sfn "$(readlink -f "$entry")" "$dest/$name"
    fi
  done
}

build_overlay() {
  local variant=$1 src=$2 dest=$3 entry name
  if [[ -d "$dest" && ! -f "$dest/.papirus-thin" ]]; then
    echo "papirus-thin: 跳过 $dest（已存在且不是本模板建的目录）" >&2
    return 0
  fi
  rm -rf "$dest"
  mkdir -p "$dest"
  cp -f "$src/index.theme" "$dest/index.theme"
  touch "$dest/.papirus-thin"
  for entry in "$src"/*; do
    [[ -e "$entry" || -L "$entry" ]] || continue
    name="${entry##*/}"
    case "$name" in
      index.theme | icon-theme.cache) continue ;;
    esac
    case "$name" in
      *@2x)
        base="${name%@2x}"
        if [[ " $SIZES " == *" $base "* ]]; then
          ln -sfn "$dest/$base" "$dest/$name"
        else
          ln -sfn "$(readlink -f "$entry")" "$dest/$name"
        fi
        ;;
      *)
        case " $SIZES " in
          *" $name "*) build_size "$entry" "$dest/$name" ;;
          *) ln -sfn "$(readlink -f "$entry")" "$dest/$name" ;;
        esac
        ;;
    esac
  done
  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -qf "$dest" >/dev/null 2>&1 || true
  fi
}

for variant in Papirus Papirus-Dark Papirus-Light; do
  src="$(find_src "$variant")" || continue
  build_overlay "$variant" "$src" "$HOME/.local/share/icons/$variant"
done

# 和上游模板一样切换 gsettings 的亮暗变体
if command -v gsettings >/dev/null 2>&1; then
  gsettings set org.gnome.desktop.interface icon-theme "$ACTIVE" 2>/dev/null || true
fi
