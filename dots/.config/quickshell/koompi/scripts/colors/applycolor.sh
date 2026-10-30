#!/usr/bin/env bash

QUICKSHELL_CONFIG_NAME="koompi"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
CONFIG_DIR="$XDG_CONFIG_HOME/quickshell/$QUICKSHELL_CONFIG_NAME"
STATE_DIR="$XDG_STATE_HOME/quickshell"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

term_alpha=100 #Set this to < 100 make all your terminals transparent
# sleep 0 # idk i wanted some delay or colors dont get applied properly
if [ ! -d "$STATE_DIR"/user/generated ]; then
  mkdir -p "$STATE_DIR"/user/generated
fi
cd "$CONFIG_DIR" || exit

colornames=''
colorstrings=''
colorlist=()
colorvalues=()

colornames=$(cut -d: -f1 "$STATE_DIR/user/generated/material_colors.scss")
colorstrings=$(cut -d: -f2 "$STATE_DIR/user/generated/material_colors.scss" | cut -d ' ' -f2 | cut -d ";" -f1)
IFS=$'\n'
# shellcheck disable=SC2206 # deliberate split on IFS=$'\n'; word splitting also drops
# blank lines, which mapfile would keep as empty entries and turn into a `sed s/ #/`
colorlist=($colornames)     # Array of color names
# shellcheck disable=SC2206 # same as above, must stay index-aligned with colorlist
colorvalues=($colorstrings) # Array of color values

apply_kitty() {  
  # Check if terminal escape sequence template exists
  if [ ! -f "$SCRIPT_DIR/terminal/kitty-theme.conf" ]; then
    echo "Template file not found for Kitty theme. Skipping that."
    return
  fi
  # Copy template
  mkdir -p "$STATE_DIR"/user/generated/terminal
  cp "$SCRIPT_DIR/terminal/kitty-theme.conf" "$STATE_DIR"/user/generated/terminal/kitty-theme.conf
  # Apply colors
  for i in "${!colorlist[@]}"; do
    sed -i "s/${colorlist[$i]} #/${colorvalues[$i]#\#}/g" "$STATE_DIR"/user/generated/terminal/kitty-theme.conf
  done

  # Reload. -x so we only match the kitty binary: `pgrep -f kitty` used to match any
  # command line merely mentioning kitty, then `pidof kitty` found nothing and kill errored.
  pkill -USR1 -x kitty || true
}

# Konsole and wezterm ship a KOOMPI scheme of their own, which this palette
# would repaint. The terminal is the parent of the pty's session leader, not
# whatever the environment says: a terminal's variables reach everything
# started from a shell inside it. config.fish asks the same question.
keeps_own_scheme() {
  local leader parent
  leader="$(ps -o sid= -t "${1#/dev/}" 2>/dev/null | head -n1 | tr -d ' ')"
  [[ -n "$leader" ]] || return 1
  parent="$(ps -o ppid= -p "$leader" 2>/dev/null | tr -d ' ')"
  [[ -n "$parent" ]] || return 1
  case "$(ps -o comm= -p "$parent" 2>/dev/null)" in
    konsole | wezterm-gui) return 0 ;;
  esac
  return 1
}

apply_anyterm() {
  # Check if terminal escape sequence template exists
  if [ ! -f "$SCRIPT_DIR/terminal/sequences.txt" ]; then
    echo "Template file not found for Terminal. Skipping that."
    return
  fi
  # Copy template
  mkdir -p "$STATE_DIR"/user/generated/terminal
  cp "$SCRIPT_DIR/terminal/sequences.txt" "$STATE_DIR"/user/generated/terminal/sequences.txt
  # Apply colors
  for i in "${!colorlist[@]}"; do
    sed -i "s/${colorlist[$i]} #/${colorvalues[$i]#\#}/g" "$STATE_DIR"/user/generated/terminal/sequences.txt
  done

  sed -i "s/\$alpha/$term_alpha/g" "$STATE_DIR/user/generated/terminal/sequences.txt"

  for file in /dev/pts/*; do
    if [[ $file =~ ^/dev/pts/[0-9]+$ ]] && ! keeps_own_scheme "$file"; then
      {
      cat "$STATE_DIR"/user/generated/terminal/sequences.txt >"$file"
      } & disown || true
    fi
  done
}

apply_term() {
  apply_anyterm &
  apply_kitty &
}

# Check if terminal theming is enabled in config
CONFIG_FILE="$XDG_CONFIG_HOME/koompi/config.json"
if [ -f "$CONFIG_FILE" ]; then
  enable_terminal=$(jq -r '.appearance.wallpaperTheming.enableTerminal' "$CONFIG_FILE")
  if [ "$enable_terminal" = "true" ]; then
    apply_term &
  fi
else
  echo "Config file not found at $CONFIG_FILE. Applying terminal theming by default."
  apply_term &
fi

# apply_qt & # Qt theming is handled by switchwall.sh (qt6ct.conf + kdeglobals merge)
