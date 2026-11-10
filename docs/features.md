# Features

This document gives an overview over Alacritty's features beyond its terminal
emulation capabilities. To get a list with supported control sequences take a
look at the [alacritty-escapes(7) manpage].

[alacritty-escapes(7) manpage]: ../extra/man/alacritty-escapes.7.scd

## Vi Mode

The vi mode allows moving around Alacritty's viewport and scrollback using the
keyboard. It also serves as a jump-off point for other features like search and
opening URLs with the keyboard. By default you can launch it using
<kbd>Ctrl</kbd> <kbd>Shift</kbd> <kbd>Space</kbd>.

### Motion

The cursor motions are setup by default to mimic vi, however they are fully
configurable. If you don't like vi's bindings, take a look at the configuration
file to change the various movements.

### Selection

One useful feature of vi mode is the ability to make selections and copy text to
the clipboard. By default you can start a selection using <kbd>v</kbd> and copy
it using <kbd>y</kbd>. All selection modes that are available with the mouse can
be accessed from vi mode, including the semantic (<kbd>Alt</kbd> <kbd>v</kbd>),
line (<kbd>Shift</kbd> <kbd>v</kbd>) and block selection (<kbd>Ctrl</kbd>
<kbd>v</kbd>). You can also toggle between them while the selection is still
active.

## Search

Search allows you to find anything in Alacritty's scrollback buffer. You can
search forward using <kbd>Ctrl</kbd> <kbd>Shift</kbd> <kbd>f</kbd> (<kbd>Command</kbd> <kbd>f</kbd> on macOS) and
backward using <kbd>Ctrl</kbd> <kbd>Shift</kbd> <kbd>b</kbd> (<kbd>Command</kbd> <kbd>b</kbd> on macOS).

### Vi Search

In vi mode the search is bound to <kbd>/</kbd> for forward and <kbd>?</kbd> for
backward search. This allows you to move around quickly and help with selecting
content. The `SearchStart` and `SearchEnd` keybinding actions can be bound if
you're looking for a way to jump to the start or the end of a match.

### Normal Search

During normal search you don't have the opportunity to move around freely, but
you can still jump between matches using <kbd>Enter</kbd> and <kbd>Shift</kbd>
<kbd>Enter</kbd>. After leaving search with <kbd>Escape</kbd> your active match
stays selected, allowing you to easily copy it.

## Hints

Terminal hints allow easily interacting with visible text without having to
start vi mode. They consist of a regex that detects these text elements and then
either feeds them to an external application or triggers one of Alacritty's
built-in actions.

Hints can also be triggered using the mouse or vi mode cursor. If a hint is
enabled for mouse interaction and recognized as such, it will be underlined when
the mouse or vi mode cursor is on top of it. Using the left mouse button or
<kbd>Enter</kbd> key in vi mode will then trigger the hint.

Hints can be configured in the `hints` and `colors.hints` sections in the
Alacritty configuration file.

## Selection expansion

After making a selection, you can use the right mouse button to expand it.
Double-clicking will expand the selection semantically, while triple-clicking
will perform line selection. If you hold <kbd>Ctrl</kbd> while expanding the
selection, it will switch to the block selection mode.

## Opening URLs with the mouse

You can open URLs with your mouse by clicking on them. The modifiers required to
be held and program which should open the URL can be setup in the configuration
file. If an application captures your mouse clicks, which is indicated by a
change in mouse cursor shape, you're required to hold <kbd>Shift</kbd> to bypass
that.

## Multi-Window

Alacritty supports running multiple terminal emulators from the same Alacritty
instance. New windows can be created either by using the `CreateNewWindow`
keybinding action, or by executing the `alacritty msg create-window` subcommand.

## Shell History Modes (fork feature)

This fork ships an optional zsh integration that gives you two shell history
modes, switchable at any prompt with a keyboard shortcut:

- **global** — the usual shared history file (`$HISTFILE`) for every directory.
- **perdir** — commands are recorded in a per-directory history file, and
  history search (`↑`/`↓`, `zsh-history-substring-search`) only offers entries
  that were run in the current directory.

While in per-directory mode every command is still appended to the global
history too (dual write), so the global history never loses entries. The last
used mode is remembered per terminal.

### Setup

1. Source the integration from your `~/.zshrc` (order relative to other
   plugins, like `zsh-history-substring-search`, does not matter):

   ```zsh
   source /path/to/alacritty/extra/zsh/alacritty-histmode.zsh
   ```

2. Toggle the mode with <kbd>Ctrl</kbd> <kbd>Shift</kbd> <kbd>H</kbd>. This
   binding is bound to the `ToggleHistoryMode` action by default and sends the
   CSI sequence `ESC [ 9000 ~` to the terminal, which the zsh integration
   binds to the `alacritty-histmode-toggle` widget.

Per-directory history files are stored as readable mirrored paths under
`${XDG_DATA_HOME:-~/.local/share}/alacritty/histmode/perdir/<dir>/history`.

### Configuration

All knobs are environment variables set before sourcing the script:

| Variable | Default | Description |
|---|---|---|
| `ALACRITTY_HISTMODE` | `global` | initial mode (`global` or `perdir`) |
| `ALACRITTY_HISTMODE_DIR` | `~/.local/share/alacritty/histmode` | base directory |
| `ALACRITTY_HISTMODE_GLOBAL` | `$HISTFILE` | global history file |
| `ALACRITTY_HISTMODE_DUAL_WRITE` | `1` | also append to the global history in per-directory mode |
| `ALACRITTY_HISTMODE_PERSIST` | `1` | remember the mode per terminal (`$TTY`) |

The current mode is exposed as `$alacritty_histmode` for use in prompts, e.g.
`PS1='%~ [%alacritty_histmode] %# '`.

The Alacritty binding can be changed or disabled through the usual
`[keyboard]` bindings table using the `ToggleHistoryMode` action. Without the
zsh integration loaded, pressing the shortcut inserts the raw sequence into
the shell, so keep the script sourced if you keep the default binding.

The integration is compatible with `EXTENDED_HISTORY`, `INC_APPEND_HISTORY`
and `SHARE_HISTORY`, and a regression suite (`extra/zsh/test-histmode.zsh`)
verifies the whole flow inside a real pseudo-terminal.

### How it works

The widget switches the active zsh history list between the global file and
the per-directory file for the current `$PWD` (following `cd` via `chpwd`),
using zsh's documented `fc -p`/`fc -P` history stack primitives:

- Entering per-directory mode pushes a new history list initialized from the
  per-directory file.
- The `zshaddhistory` hook adds each accepted command to the active list and
  appends it to the right file(s), matching zsh's history file format.
- Leaving the mode flushes pending entries, pops back to the global list and
  refreshes it from the global file.
