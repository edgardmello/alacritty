#!/usr/bin/env python3
"""PTY driver for the alacritty-histmode test suite.

Runs an interactive zsh inside a real pseudo-terminal, feeds input with
timing control (including raw escape sequences), waits for a clean child
exit, and prints everything the child wrote to a log file.

Spec (JSON on stdin):
    {
        "cwd":   "/working/directory",
        "env":   {"VAR": "value", ...},
        "shell": "/bin/zsh",
        "args":  ["-f", "-i"],
        "steps": [{"send": "command\n", "delay": 0.4}, ...],
        "log":   "/path/to/child-output.log"
    }

"send" is written verbatim (escape sequences allowed); "delay" is the
pause after the write, in seconds.
"""

import json
import os
import select
import sys
import time
import pty


def main() -> int:
    spec = json.load(sys.stdin)

    pid, fd = pty.fork()
    if pid == 0:
        cwd = spec.get("cwd") or "."
        os.chdir(cwd)
        # Real terminals inherit $PWD; without it zsh resolves the physical
        # path (e.g. /private/tmp instead of /tmp on macOS), which would
        # change the per-directory history file names.
        os.environ["PWD"] = cwd
        for key, value in spec.get("env", {}).items():
            os.environ[key] = value
        shell = spec.get("shell", "/bin/zsh")
        os.execv(shell, [shell] + spec.get("args", ["-f", "-i"]))

    log = open(spec.get("log", "/dev/null"), "wb")

    def drain(timeout: float) -> None:
        while select.select([fd], [], [], timeout)[0]:
            try:
                data = os.read(fd, 4096)
            except OSError:
                return
            if not data:
                return
            log.write(data)

    time.sleep(0.6)
    drain(0.3)
    for step in spec.get("steps", []):
        payload = step.get("send", "")
        if payload:
            os.write(fd, payload.encode())
        time.sleep(step.get("delay", 0.3))
        drain(0.1)

    # Wait for the child to exit on its own; keep draining meanwhile.
    deadline = time.time() + 10
    while time.time() < deadline:
        drain(0.2)
        waited, status = os.waitpid(pid, os.WNOHANG)
        if waited == pid:
            log.close()
            os.close(fd)
            return os.waitstatus_to_exitcode(status)
    os.close(fd)
    log.close()
    return 1


if __name__ == "__main__":
    sys.exit(main())
