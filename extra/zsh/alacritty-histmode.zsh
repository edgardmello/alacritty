# alacritty-histmode.zsh — global + per-directory history for Alacritty.
#
# Part of the Alacritty fork; pairs with the `ToggleHistoryMode` key binding
# (default: Ctrl+Shift+H), which sends the CSI sequence `\e[9000~` to the
# terminal. This script binds that sequence to a zle widget that switches
# the active history between:
#
#   global  — one shared history for every directory (your usual $HISTFILE).
#   perdir  — commands are recorded in a per-directory history file and
#             ↑/↓ (and zsh-history-substring-search) only see entries from
#             the current directory.
#
# While in per-directory mode every command is still appended to the global
# history too (dual write), so the global history never loses entries.
#
# Usage (in ~/.zshrc, order relative to other plugins does not matter):
#
#   source /path/to/alacritty-histmode.zsh
#
# Configuration (set before sourcing):
#
#   ALACRITTY_HISTMODE             initial mode: `global` or `perdir`
#                                  (default: `global`; the last toggled mode
#                                  is remembered per terminal, see below)
#   ALACRITTY_HISTMODE_DIR         base directory for per-directory files
#                                  (default: ${XDG_DATA_HOME:-~/.local/share}/alacritty/histmode)
#   ALACRITTY_HISTMODE_GLOBAL      file used as the global history
#                                  (default: $HISTFILE, or ~/.zsh_history)
#   ALACRITTY_HISTMODE_DUAL_WRITE  when in per-directory mode, also append
#                                  every command to the global history
#                                  (default: 1)
#   ALACRITTY_HISTMODE_PERSIST     remember the toggled mode per terminal
#                                  (per $TTY) across shells (default: 1)
#
# Exposed for prompts:
#
#   $alacritty_histmode   current mode, `global` or `perdir`, e.g.
#                         PS1="%~ [%alacritty_histmode] %# "
#
# Compatibility:
#   * Works with EXTENDED_HISTORY on or off, and with INC_APPEND_HISTORY /
#     SHARE_HISTORY — entries written incrementally are never duplicated,
#     and without them pending entries are flushed on toggle/exit.
#   * zsh-history-substring-search searches the live history list, so it
#     automatically follows the active mode; the toggle sequence does not
#     collide with its ↑/↓ bindings.

# Do not load twice.
if [[ -n ${_alacritty_histmode_loaded:-} ]]; then
  return 0
fi
typeset -g _alacritty_histmode_loaded=1

emulate -L zsh

autoload -Uz add-zsh-hook

typeset -g alacritty_histmode=global
typeset -g _ahd_base=${ALACRITTY_HISTMODE_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/alacritty/histmode}
typeset -g _ahd_global=${ALACRITTY_HISTMODE_GLOBAL:-${HISTFILE:-$HOME/.zsh_history}}
typeset -g _ahd_pushed=0        # per-directory list currently pushed with fc -p
typeset -g _ahd_cur=""          # currently loaded per-directory file
typeset -g _ahd_started=0       # first precmd seen (history is loaded)

# Keep zsh's own saving pointed at the global file unless we push per-dir.
[[ -n $HISTFILE ]] || typeset -g HISTFILE=$_ahd_global

_ahd_perdir_file() {
  # History file for the given directory. Each tracked directory maps to
  # a directory (not a file) so nested paths never collide, e.g.
  #   $base/perdir/home/user/project/history
  #   $base/perdir/home/user/project/sub/history
  local dir=${${1:-$PWD}:-/}
  if [[ $dir == / ]]; then
    print -r -- "$_ahd_base/perdir/_root/history"
  else
    print -r -- "$_ahd_base/perdir$dir/history"
  fi
}

_ahd_state_file() {
  local tty=${TTY:-no-tty}
  print -r -- "$_ahd_base/state/${tty//[^a-zA-Z0-9]/_}"
}

_ahd_mkdir_for() {
  # fc refuses to write when the parent directory is missing.
  [[ -d ${1:h} ]] || mkdir -p -- ${1:h} 2>/dev/null
}

_ahd_incremental() {
  # With these options every accepted line is already on disk when the
  # zshaddhistory hook returns; flushing again would duplicate entries.
  [[ -o incappendhistory || -o sharehistory || -o incappendhistorytime ]]
}

_ahd_deactivate() {
  # Return to the global history list.
  (( _ahd_pushed )) || return 0
  _ahd_mkdir_for "$_ahd_cur"
  _ahd_incremental || fc -AI "$_ahd_cur" 2>/dev/null
  # Pop without saving: pending events were flushed above, and pop-save
  # would duplicate entries appended incrementally.
  unset HISTFILE
  fc -P
  _ahd_pushed=0
  _ahd_cur=""
  # Refresh the global list with anything new (other shells, dual writes).
  [[ -f $_ahd_global ]] && fc -RI "$_ahd_global" 2>/dev/null
}

_ahd_activate() {
  # Switch to the per-directory file for the current $PWD.
  local file
  file=$(_ahd_perdir_file "$PWD")
  [[ $file == $_ahd_cur ]] && return 0
  _ahd_deactivate
  _ahd_mkdir_for "$file"
  fc -p "$file"
  _ahd_pushed=1
  _ahd_cur=$file
}

_ahd_apply() {
  if [[ $alacritty_histmode == perdir ]]; then
    _ahd_activate
  else
    _ahd_deactivate
  fi
}

_ahd_save_state() {
  (( ${ALACRITTY_HISTMODE_PERSIST:-1} )) || return 0
  _ahd_mkdir_for "$_ahd_base/state/x"
  print -r -- "$alacritty_histmode" > "$(_ahd_state_file)" 2>/dev/null
}

_ahd_restore_state() {
  alacritty_histmode=${ALACRITTY_HISTMODE:-global}
  if (( ${ALACRITTY_HISTMODE_PERSIST:-1} )); then
    local state=$(_ahd_state_file)
    if [[ -r $state ]]; then
      read -r alacritty_histmode < $state
    fi
  fi
  [[ $alacritty_histmode == perdir ]] || alacritty_histmode=global
}

_ahd_zshaddhistory() {
  # Canonical zsh pattern (see zshmisc(1), zshaddhistory): add a clean copy
  # to the active list, then switch the write context so zsh itself appends
  # the accepted line to the right file.
  local line=${1%%$'\n'}
  print -sr -- "$line"
  if (( _ahd_pushed )); then
    # Line goes to the per-directory file...
    fc -p "$_ahd_cur"
    # ...and, for a complete global history, also to the global file.
    if (( ${ALACRITTY_HISTMODE_DUAL_WRITE:-1} )) && [[ -n $_ahd_global ]]; then
      local prefix=''
      if [[ -o extendedhistory || -o sharehistory || -o incappendhistorytime ]]; then
        zmodload -F zsh/datetime b:EPOCHSECONDS 2>/dev/null
        prefix=": ${EPOCHSECONDS:-0}:0;"
      fi
      # Match zsh's history file format: embedded newlines escaped by `\`.
      _ahd_mkdir_for "$_ahd_global"
      print -r -- "$prefix${line//$'\n'/$'\\\n'}" >> "$_ahd_global"
    fi
  else
    fc -p "$_ahd_global"
  fi
  return 0
}

_ahd_chpwd() {
  # Only acts in per-directory mode when the target file differs.
  _ahd_apply
}

_ahd_precmd() {
  if (( ! _ahd_started )); then
    # zsh loads $HISTFILE after the rc files; switch modes once it is ready.
    _ahd_started=1
    _ahd_restore_state
    _ahd_apply
    return
  fi
  # Catch directory changes that bypass chpwd hooks.
  [[ $alacritty_histmode == perdir ]] && _ahd_apply
}

_ahd_zshexit() {
  # Flush the per-directory list, restore the global list, then flush any
  # pending global entries (zshexit runs before the final history save).
  _ahd_deactivate
  _ahd_incremental || fc -AI "$_ahd_global" 2>/dev/null
}

alacritty-histmode-toggle() {
  if [[ $alacritty_histmode == perdir ]]; then
    alacritty_histmode=global
  else
    alacritty_histmode=perdir
  fi
  _ahd_apply
  _ahd_save_state
  zle -M "history: $alacritty_histmode"
  # Refresh prompts that display $alacritty_histmode.
  zle reset-prompt
}

if [[ -o interactive ]]; then
  zle -N alacritty-histmode-toggle

  # Sequence sent by Alacritty's ToggleHistoryMode action.
  _ahd_seq=$'\e[9000~'
  bindkey -M emacs "$_ahd_seq" alacritty-histmode-toggle
  bindkey -M viins "$_ahd_seq" alacritty-histmode-toggle
  bindkey -M vicmd "$_ahd_seq" alacritty-histmode-toggle
  unset _ahd_seq

  add-zsh-hook precmd _ahd_precmd
  add-zsh-hook chpwd _ahd_chpwd
  add-zsh-hook zshexit _ahd_zshexit
  add-zsh-hook zshaddhistory _ahd_zshaddhistory
fi
