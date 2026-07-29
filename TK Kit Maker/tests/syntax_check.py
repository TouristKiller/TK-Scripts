#!/usr/bin/env python3
"""Compiles every Lua file in the project.

Catches typos and unbalanced blocks without opening REAPER -- which otherwise
only reports them when the offending screen is drawn.
"""

import glob
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def check(root=ROOT, quiet=False):
    from lupa import LuaRuntime
    lua = LuaRuntime()
    compile_ = lua.eval("function(src, name)"
                        "  local f, e = load(src, name)"
                        "  if f then return true else return e end"
                        " end")

    paths = sorted(glob.glob(os.path.join(root, "**", "*.lua"), recursive=True))
    bad = 0
    for path in paths:
        src = open(path, encoding="utf-8", errors="surrogateescape").read()
        result = compile_(src, "@" + path)
        if result is not True:
            bad += 1
            print("SYNTAX ERROR  %s\n    %s" % (os.path.relpath(path, root), result))

    if not quiet:
        print("checked %d files, %d with errors" % (len(paths), bad))
    return bad


if __name__ == "__main__":
    sys.exit(1 if check() else 0)
