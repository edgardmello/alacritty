#!/usr/bin/env zsh
# test-histmode.zsh — test suite for alacritty-histmode.zsh.
#
# Drives real interactive zsh sessions inside a pty, sends the actual
# toggle escape sequence, and asserts on the resulting history files.
#
# Usage: zsh extra/zsh/test-histmode.zsh

emulate -L zsh

local SCRIPT_DIR=${0:A:h}
local AHD_SCRIPT=$SCRIPT_DIR/alacritty-histmode.zsh
local DRIVER=$SCRIPT_DIR/histmode-pty-driver.py
local TESTROOT=${TESTROOT:-$(mktemp -d /tmp/alacritty-histmode-test.XXXXXX)}
local ZSH_BIN=${ZSH_BIN:-/bin/zsh}
local PYTHON=${PYTHON:-python3}

typeset -gi PASS=0 FAIL=0

ok()  { ((PASS+=1)); print "PASS  $1" }
bad() { ((FAIL+=1)); print "FAIL  $1" }

assert_eq() {  # desc expected actual
  if [[ $2 == $3 ]]; then ok "$1"; else bad "$1 — expected |$2|, got |$3|"; fi
}

assert_contains_once() {  # desc file string
  local count
  count=$(grep -cF -- "$3" "$2" 2>/dev/null) || count=0
  if [[ $count == 1 ]]; then ok "$1"; else bad "$1 — '$3' found $count times in $2"; fi
}

assert_absent() {  # desc file string
  if grep -qF -- "$3" "$2" 2>/dev/null; then
    bad "$1 — '$3' unexpectedly present in $2"
  else
    ok "$1"
  fi
}

# run_session <testdir> [env assignments...] ; session steps on stdin (JSON)
run_session() {
  local dir=$1; shift
  local -a env
  env=(HISTSIZE=1000 SAVEHIST=1000 PS1='$ ' "$@")
  local spec_file=$dir/spec.json
  cat > $spec_file
  $PYTHON - "$dir" "$spec_file" <<EOF
import json, subprocess, sys
env = [${(j:, :)${(@qq)env}}]
spec = {"steps": json.load(open(sys.argv[2]))}
spec.update({"cwd": sys.argv[1], "env": dict(e.split("=", 1) for e in env),
             "shell": "$ZSH_BIN", "log": sys.argv[1] + "/session.log"})
p = subprocess.run(["$PYTHON", "$DRIVER"], input=json.dumps(spec).encode())
sys.exit(p.returncode)
EOF
}

# ---------------------------------------------------------------------------
# T0: syntax check
if zsh -n $AHD_SCRIPT 2>/dev/null; then
  ok "T0: script parses"
else
  bad "T0: script parses"
fi

# ---------------------------------------------------------------------------
# T1: default mode is global; commands land in the global history only.
local T=$TESTROOT/t1; mkdir -p $T
run_session $T HISTFILE=$T/global.hist ALACRITTY_HISTMODE_DIR=$T/ahd \
  ALACRITTY_HISTMODE_PERSIST=0 <<EOF
[
  {"send": "source $AHD_SCRIPT\n", "delay": 0.4},
  {"send": "t1-global-cmd\n", "delay": 0.3},
  {"send": "print -r -- \"MODE=\$alacritty_histmode\" > $T/marker\n", "delay": 0.3},
  {"send": "exit\n", "delay": 0.6}
]
EOF
assert_eq "T1: initial mode" "MODE=global" "$(cat $T/marker 2>/dev/null)"
assert_contains_once "T1: command in global history" $T/global.hist "t1-global-cmd"
if [[ ! -d $T/ahd/perdir ]]; then
  ok "T1: no per-directory files created"
else
  bad "T1: no per-directory files created — $(ls $T/ahd/perdir)"
fi

# ---------------------------------------------------------------------------
# T2: the toggle sequence switches to per-directory mode; dual write keeps
# the global history complete; the per-dir file holds only local entries.
local T=$TESTROOT/t2; mkdir -p $T
run_session $T HISTFILE=$T/global.hist ALACRITTY_HISTMODE_DIR=$T/ahd \
  ALACRITTY_HISTMODE_PERSIST=0 <<EOF
[
  {"send": "source $AHD_SCRIPT\n", "delay": 0.4},
  {"send": "t2-before-toggle\n", "delay": 0.3},
  {"send": "\u001b[9000~", "delay": 0.4},
  {"send": "t2-perdir-cmd\n", "delay": 0.3},
  {"send": "print -r -- \"MODE=\$alacritty_histmode FC=\$(fc -ln -1)\" > $T/marker\n", "delay": 0.3},
  {"send": "exit\n", "delay": 0.6}
]
EOF
assert_eq "T2: mode after first toggle" "MODE=perdir" "${$(cat $T/marker 2>/dev/null)%% FC=*}"
assert_contains_once "T2: per-dir command in per-dir file" $T/ahd/perdir$T/history "t2-perdir-cmd"
assert_absent "T2: pre-toggle command stays out of per-dir file" $T/ahd/perdir$T/history "t2-before-toggle"
assert_contains_once "T2: dual write to global history" $T/global.hist "t2-perdir-cmd"
assert_eq "T2: last entry searched is per-dir" "t2-perdir-cmd" "${$(cat $T/marker 2>/dev/null)##*FC=}"

# ---------------------------------------------------------------------------
# T3: toggle back to global; new commands go to global only; ↑ history sees
# everything (global entries + dual-written per-dir entries).
local T=$TESTROOT/t3; mkdir -p $T
run_session $T HISTFILE=$T/global.hist ALACRITTY_HISTMODE_DIR=$T/ahd \
  ALACRITTY_HISTMODE_PERSIST=0 <<EOF
[
  {"send": "source $AHD_SCRIPT\n", "delay": 0.4},
  {"send": "\u001b[9000~", "delay": 0.4},
  {"send": "t3-perdir-cmd\n", "delay": 0.3},
  {"send": "\u001b[9000~", "delay": 0.4},
  {"send": "t3-global-cmd\n", "delay": 0.3},
  {"send": "print -r -- \"MODE=\$alacritty_histmode FC=\$(fc -ln -1)\" > $T/marker\n", "delay": 0.3},
  {"send": "exit\n", "delay": 0.6}
]
EOF
assert_eq "T3: mode after second toggle" "MODE=global" "${$(cat $T/marker 2>/dev/null)%% FC=*}"
assert_eq "T3: last entry is global" "t3-global-cmd" "${$(cat $T/marker 2>/dev/null)##*FC=}"
assert_contains_once "T3: per-dir entry visible in global mode (dual write)" $T/global.hist "t3-perdir-cmd"
assert_contains_once "T3: no duplicate entries in global" $T/global.hist "t3-global-cmd"
assert_absent "T3: global command not appended to per-dir file" $T/ahd/perdir$T/history "t3-global-cmd"

# ---------------------------------------------------------------------------
# T4: in per-directory mode, cd switches the active history file.
local T=$TESTROOT/t4; mkdir -p $T/sub
run_session $T HISTFILE=$T/global.hist ALACRITTY_HISTMODE_DIR=$T/ahd \
  ALACRITTY_HISTMODE_PERSIST=0 <<EOF
[
  {"send": "source $AHD_SCRIPT\n", "delay": 0.4},
  {"send": "\u001b[9000~", "delay": 0.4},
  {"send": "t4-outer-cmd\n", "delay": 0.3},
  {"send": "cd $T/sub\n", "delay": 0.3},
  {"send": "t4-sub-cmd\n", "delay": 0.3},
  {"send": "print -r -- \"FC=\$(fc -ln -1)\" > $T/marker\n", "delay": 0.3},
  {"send": "exit\n", "delay": 0.6}
]
EOF
assert_contains_once "T4: outer command in outer per-dir file" $T/ahd/perdir$T/history "t4-outer-cmd"
assert_contains_once "T4: sub command in sub per-dir file" $T/ahd/perdir$T/sub/history "t4-sub-cmd"
assert_absent "T4: sub command not in outer per-dir file" $T/ahd/perdir$T/history "t4-sub-cmd"
assert_eq "T4: last entry after cd is from sub history" "t4-sub-cmd" "${$(cat $T/marker 2>/dev/null)##*FC=}"
assert_contains_once "T4: dual write follows cd" $T/global.hist "t4-sub-cmd"

# ---------------------------------------------------------------------------
# T5: mode persists per terminal ($TTY) across nested shells.
local T=$TESTROOT/t5; mkdir -p $T
: > $T/marker
run_session $T HISTFILE=$T/global.hist ALACRITTY_HISTMODE_DIR=$T/ahd \
  ALACRITTY_HISTMODE_PERSIST=1 <<EOF
[
  {"send": "source $AHD_SCRIPT\n", "delay": 0.4},
  {"send": "\u001b[9000~", "delay": 0.4},
  {"send": "t5-perdir-cmd\n", "delay": 0.3},
  {"send": "ZDOTDIR=/nonexistent HISTFILE=$T/global.hist HISTSIZE=1000 SAVEHIST=1000 ALACRITTY_HISTMODE_DIR=$T/ahd $ZSH_BIN -f -i\n", "delay": 0.6},
  {"send": "source $AHD_SCRIPT\n", "delay": 0.6},
  {"send": "print -r -- \"INNER=\$alacritty_histmode\" >> $T/marker\n", "delay": 0.3},
  {"send": "exit\n", "delay": 0.4},
  {"send": "exit\n", "delay": 0.6}
]
EOF
assert_eq "T5: nested shell restores per-terminal mode" "INNER=perdir" "$(grep INNER $T/marker 2>/dev/null | tail -1)"

# ---------------------------------------------------------------------------
# T6: without EXTENDED_HISTORY the dual-written lines stay plain text.
local T=$TESTROOT/t6; mkdir -p $T
run_session $T HISTFILE=$T/global.hist ALACRITTY_HISTMODE_DIR=$T/ahd \
  ALACRITTY_HISTMODE_PERSIST=0 <<EOF
[
  {"send": "setopt no_extendedhistory\n", "delay": 0.3},
  {"send": "source $AHD_SCRIPT\n", "delay": 0.4},
  {"send": "\u001b[9000~", "delay": 0.4},
  {"send": "t6-plain-cmd\n", "delay": 0.3},
  {"send": "exit\n", "delay": 0.6}
]
EOF
assert_contains_once "T6: plain-format dual write" $T/global.hist "t6-plain-cmd"
if ! grep -q '^:' $T/global.hist; then
  ok "T6: no extended-history markers when option is off"
else
  bad "T6: unexpected extended-history markers"
fi

# ---------------------------------------------------------------------------
# T7: SHARE_HISTORY never duplicates entries across repeated toggles.
local T=$TESTROOT/t7; mkdir -p $T
run_session $T HISTFILE=$T/global.hist ALACRITTY_HISTMODE_DIR=$T/ahd \
  ALACRITTY_HISTMODE_PERSIST=0 <<EOF
[
  {"send": "setopt sharehistory\n", "delay": 0.3},
  {"send": "source $AHD_SCRIPT\n", "delay": 0.4},
  {"send": "\u001b[9000~", "delay": 0.3},
  {"send": "t7-perdir-1\n", "delay": 0.3},
  {"send": "\u001b[9000~", "delay": 0.3},
  {"send": "t7-global-1\n", "delay": 0.3},
  {"send": "\u001b[9000~", "delay": 0.3},
  {"send": "t7-perdir-2\n", "delay": 0.3},
  {"send": "\u001b[9000~", "delay": 0.3},
  {"send": "t7-global-2\n", "delay": 0.3},
  {"send": "exit\n", "delay": 0.6}
]
EOF
assert_contains_once "T7: per-dir file has no duplicate of first entry" $T/ahd/perdir$T/history "t7-perdir-1"
assert_contains_once "T7: per-dir file has no duplicate of second entry" $T/ahd/perdir$T/history "t7-perdir-2"
assert_contains_once "T7: global has no duplicate of per-dir dual write" $T/global.hist "t7-perdir-1"
assert_contains_once "T7: global has no duplicate of global entry" $T/global.hist "t7-global-1"

# ---------------------------------------------------------------------------
# T8: multi-line commands survive the dual write as a single entry.
local T=$TESTROOT/t8; mkdir -p $T
run_session $T HISTFILE=$T/global.hist ALACRITTY_HISTMODE_DIR=$T/ahd \
  ALACRITTY_HISTMODE_PERSIST=0 <<EOF
[
  {"send": "source $AHD_SCRIPT\n", "delay": 0.4},
  {"send": "\u001b[9000~", "delay": 0.4},
  {"send": "echo t8-multi \\\\\n", "delay": 0.3},
  {"send": "line-two\n", "delay": 0.5},
  {"send": "exit\n", "delay": 0.6}
]
EOF
local FC_COUNT
FC_COUNT=$($ZSH_BIN -f -i -c "fc -RI $T/global.hist; fc -ln | grep -cF 't8-multi'" </dev/null 2>/dev/null)
assert_eq "T8: multiline entry round-trips as one event" "1" "$FC_COUNT"

# ---------------------------------------------------------------------------
print ""
print "Results: $PASS passed, $FAIL failed (root: $TESTROOT)"
(( FAIL == 0 ))
