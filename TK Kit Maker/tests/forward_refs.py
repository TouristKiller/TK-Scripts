#!/usr/bin/env python3
"""Finds calls to a `local function` that is defined further down the file.

Lua resolves such a name as a GLOBAL, so it is nil at run time and the call
dies with "attempt to call a nil value" -- but the file compiles cleanly, so a
syntax check says nothing. This has bitten this project, hence the check.

Names that are forward-declared (`local foo` on its own line, assigned later)
are fine and are skipped.
"""

import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

DEF = re.compile(r'\s*local function ([A-Za-z_]\w*)')
FWD = re.compile(r'\s*local ([A-Za-z_][\w,\s]*?)\s*$')


def check(root=ROOT, quiet=False):
    bad = 0
    for path in sorted(glob.glob(os.path.join(root, "**", "*.lua"), recursive=True)):
        lines = open(path, encoding="utf-8", errors="surrogateescape").read().split("\n")

        defs, forward = {}, set()
        for i, line in enumerate(lines, 1):
            m = DEF.match(line)
            if m and m.group(1) not in defs:
                defs[m.group(1)] = i
            m2 = FWD.match(line)
            if m2 and "function" not in line:
                for name in m2.group(1).split(","):
                    forward.add(name.strip())

        for name, line_no in defs.items():
            if name in forward:
                continue
            for i, line in enumerate(lines[:line_no - 1], 1):
                if re.search(r'\b%s\s*\(' % re.escape(name), line.split("--")[0]):
                    bad += 1
                    print("%s:%d  calls '%s', defined at line %d"
                          % (os.path.relpath(path, root), i, name, line_no))

    if not quiet:
        print("forward-reference problems: %d" % bad)
    return bad


if __name__ == "__main__":
    sys.exit(1 if check() else 0)
