#!/usr/bin/env bash
# papirus-thin — 为 Papirus 建薄覆盖层：只建目录骨架和 folder 链接，不复制整个主题。
# 文件夹颜色跟随 Noctalia 渲染出的 colors-final。
#
# 性能：首次（或 Papirus 包更新后）完整建一次；之后颜色变化只重写
# places 里的 folder 链接，不碰目录骨架、不重扫全部图标。
set -euo pipefail
: "${USER:=$(id -un)}"

CONFIG_DIR="$(cd "$(dirname "$0")" && pwd)"
COLOR_FILE="$CONFIG_DIR/colors-final"
[[ -f "$COLOR_FILE" ]] || exit 0

mapfile -t lines <"$COLOR_FILE"
TARGET="${lines[0]//[# ]/}"
[[ ${#TARGET} -ge 6 ]] || exit 0
TARGET="${TARGET:0:6}"

MAPPING="$(printf '%s\n' "${lines[@]}" | sed '/^[[:space:]]*$/d' | tail -n1)"

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

DEST="$HOME/.local/share/icons/Papirus"
SIZES="16x16 18x18 22x22 24x24 32x32 48x48 64x64 96x96 128x128"

# 颜色没变就跳过重写链接，但仍要保证 Dark/Light 指向 Papirus 覆盖层
SAME=0
if [[ -z "${PAPIRUS_THIN_FORCE:-}" ]] &&
  [[ -f "$DEST/48x48/places/folder.svg" ]] &&
  [[ "$(readlink -f "$DEST/48x48/places/folder.svg")" == *"/folder-$closest.svg" ]]; then
  SAME=1
fi

# 找系统 Papirus：XDG_DATA_DIRS + systemPackages / home-manager / nix profile
dirs=()
IFS=: read -ra dirs <<<"${XDG_DATA_DIRS:-}"
for d in \
  "/run/current-system/sw/share" \
  "/etc/profiles/per-user/${USER}/share" \
  "$HOME/.local/state/nix/profiles/home-manager/share" \
  "$HOME/.nix-profile/share" \
  "/usr/local/share" \
  "/usr/share"; do
  dirs+=("$d")
done

find_src() {
  local v=$1 d
  for d in "${dirs[@]}"; do
    [[ -n "$d" && -d "$d/icons/$v" ]] || continue
    readlink -f "$d/icons/$v"
    return 0
  done
  return 1
}

# folder-<颜色>.svg / folder-<颜色>-x.svg / user-<颜色>-x.svg 是颜色变体
is_color_variant() {
  local base=$1 c
  for c in "${colors[@]}"; do
    [[ "$base" == "folder-$c" || "$base" == folder-"$c"-* ]] && return 0
    [[ "$base" == "user-$c" || "$base" == user-"$c"-* ]] && return 0
  done
  return 1
}

# 把一个 places 图标解析成带 %C% 占位的目标文件名；空输出表示不参与改色。
# folder-/user- 前缀直接替换；其余别名（inode-directory 等）解析系统文件的
# 真实目标，再看它是不是默认的 blue 变体。
resolve_template() {
  local entry=$1 real rel base
  real="$(readlink -f "$entry")"
  rel="${real#"$ROOT"/}"
  case "$rel" in
    *folder-blue*) printf '%s' "${rel/folder-blue/folder-%C%}" ;;
    *user-blue*) printf '%s' "${rel/user-blue/user-%C%}" ;;
    *)
      # 本尺寸没有颜色变体（folder.svg 是真实文件）时，借用 48x48 的变体
      base="${entry##*/}"
      base="${base%.svg}"
      case "$base" in
        folder) [[ -e "$ROOT/48x48/places/folder-$closest.svg" ]] && printf '48x48/places/folder-%%C%%.svg' ;;
        folder-*) [[ -e "$ROOT/48x48/places/folder-$closest-${base#folder-}.svg" ]] && printf '48x48/places/folder-%%C%%-%s' "${base#folder-}" ;;
        user) [[ -e "$ROOT/48x48/places/user-$closest.svg" ]] && printf '48x48/places/user-%%C%%.svg' ;;
        user-*) [[ -e "$ROOT/48x48/places/user-$closest-${base#user-}.svg" ]] && printf '48x48/places/user-%%C%%-%s' "${base#user-}" ;;
      esac
      ;;
  esac
  return 0
}

# 首次构建：完整骨架 + 每个 places 的颜色目标清单（.colorfiles）
build_places_full() {
  local src=$1 dest=$2 entry name base tmpl
  mkdir -p "$dest"
  : >"$dest/.colorfiles"
  for entry in "$src"/*.svg; do
    [[ -e "$entry" || -L "$entry" ]] || continue
    name="${entry##*/}"
    base="${name%.svg}"
    is_color_variant "$base" && continue
    tmpl="$(resolve_template "$entry" "$base")"
    if [[ -n "$tmpl" ]]; then
      ln -sfn "$ROOT/${tmpl//%C%/$closest}" "$dest/$name"
      printf '%s|%s\n' "$name" "$tmpl" >>"$dest/.colorfiles"
    else
      ln -sfn "$(readlink -f "$entry")" "$dest/$name"
    fi
  done
}

build_size_full() {
  local src=$1 dest=$2 entry name
  mkdir -p "$dest"
  for entry in "$src"/*; do
    [[ -e "$entry" || -L "$entry" ]] || continue
    name="${entry##*/}"
    if [[ "$name" == places ]]; then
      build_places_full "$src/places" "$dest/places"
    else
      ln -sfn "$(readlink -f "$entry")" "$dest/$name"
    fi
  done
}

build_full() {
  local src=$1 dest=$2 entry name base
  rm -rf "$dest"
  mkdir -p "$dest"
  cp -f "$src/index.theme" "$dest/index.theme"
  printf '%s' "$src" >"$dest/.papirus-thin-src"
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
          *" $name "*) build_size_full "$entry" "$dest/$name" ;;
          *) ln -sfn "$(readlink -f "$entry")" "$dest/$name" ;;
        esac
        ;;
    esac
  done
}

# 增量：只重写颜色相关链接
build_incr() {
  local src=$1 dest=$2 size name tmpl
  for size in $SIZES; do
    [[ -f "$dest/$size/places/.colorfiles" ]] || continue
    while IFS='|' read -r name tmpl; do
      [[ -n "$name" ]] || continue
      ln -sfn "$ROOT/${tmpl//%C%/$closest}" "$dest/$size/places/$name"
    done <"$dest/$size/places/.colorfiles"
  done
}

# Dark/Light 变体：骨架沿用系统图标，places 直接指向 Papirus 覆盖层，
# 这样只维护 Papirus 的链接就够，Luciole 等按 gsettings 用 Dark 的应用也能跟随。
ensure_variant() {
  local variant=$1 vsrc=$2 vdest="$HOME/.local/share/icons/$1" entry name sub subname
  [[ -n "$vsrc" && -d "$vsrc" ]] || return 0
  if [[ -f "$vdest/.papirus-thin-src" ]] && [[ "$(cat "$vdest/.papirus-thin-src")" == "$vsrc" ]]; then
    return 0
  fi
  if [[ -d "$vdest" && ! -f "$vdest/.papirus-thin-src" ]]; then
    echo "papirus-thin: 跳过 $vdest（已存在且不是本模板建的目录）" >&2
    return 0
  fi
  rm -rf "$vdest"
  mkdir -p "$vdest"
  cp -f "$vsrc/index.theme" "$vdest/index.theme"
  printf '%s' "$vsrc" >"$vdest/.papirus-thin-src"
  for entry in "$vsrc"/*; do
    [[ -e "$entry" || -L "$entry" ]] || continue
    name="${entry##*/}"
    case "$name" in
      index.theme | icon-theme.cache) continue ;;
    esac
    case "$name" in
      *@2x)
        ln -sfn "$vdest/${name%@2x}" "$vdest/$name"
        ;;
      *)
        case " $SIZES " in
          *" $name "*)
            mkdir -p "$vdest/$name"
            ln -sfn "$DEST/$name/places" "$vdest/$name/places"
            for sub in "$entry"/*; do
              [[ -e "$sub" || -L "$sub" ]] || continue
              subname="${sub##*/}"
              [[ "$subname" == places ]] && continue
              ln -sfn "$(readlink -f "$sub")" "$vdest/$name/$subname"
            done
            ;;
          *)
            ln -sfn "$(readlink -f "$entry")" "$vdest/$name"
            ;;
        esac
        ;;
    esac
  done
}

ROOT="$(find_src Papirus)" || { echo "papirus-thin: 未找到 Papirus" >&2; exit 0; }

if [[ -d "$DEST" && ! -f "$DEST/.papirus-thin-src" ]]; then
  echo "papirus-thin: 跳过 $DEST（已存在且不是本模板建的目录）" >&2
  exit 0
fi

if [[ $SAME -eq 0 ]] && { [[ ! -f "$DEST/.papirus-thin-src" ]] || [[ "$(cat "$DEST/.papirus-thin-src")" != "$ROOT" ]]; }; then
  build_full "$ROOT" "$DEST"
  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -qf "$DEST" >/dev/null 2>&1 || true
  fi
elif [[ $SAME -eq 0 ]]; then
  build_incr "$ROOT" "$DEST"
fi

# Dark/Light：places 指向 Papirus 覆盖层，跟随颜色变化
for variant in Papirus-Dark Papirus-Light; do
  vsrc="$(find_src "$variant")" || continue
  ensure_variant "$variant" "$vsrc"
done
