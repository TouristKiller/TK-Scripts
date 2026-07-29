#!/usr/bin/env python3
"""Runs every check over TK Kit Maker: syntax, forward references, test suites.

    python tests/run_all.py

Needs Python with `lupa` (pip install lupa), which supplies the Lua interpreter.
REAPER is not involved: the suites stub the parts of its API they touch, so this
runs with REAPER closed and never reads or writes any of your samples.

Exit code is non-zero when anything fails.
"""

import glob
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

sys.path.insert(0, HERE)
import syntax_check          # noqa: E402
import forward_refs          # noqa: E402


def say(text=""):
    # Lua's print goes straight to the C stdout while Python's is buffered, so
    # without flushing the summary turns up before the output it summarises.
    print(text, flush=True)


def run_suites():
    """Returns the names of the suites that failed, or None if Lua is missing."""
    try:
        from lupa import LuaRuntime
    except ImportError:
        say("lupa is not installed -- run: pip install lupa")
        return None

    failed = []
    for path in sorted(glob.glob(os.path.join(HERE, "test_*.lua"))):
        name = os.path.basename(path)[:-4]
        say("--- %s " % name + "-" * max(0, 56 - len(name)))

        lua = LuaRuntime(unpack_returned_tuples=True)
        # How the suites find the modules they test, without a path baked in.
        lua.globals().TEST_DIR = HERE.replace("\\", "/")
        try:
            lua.execute(open(path, encoding="utf-8").read())
        except Exception as exc:
            say("LUA ERROR: %s" % exc)
            failed.append(name)
            continue

        # Each suite leaves its failure count here; going by what it printed
        # would mean trusting a string.
        count = lua.globals().TEST_FAILED
        if count is None:
            say("(suite reported nothing -- is TEST_FAILED set at the end?)")
            failed.append(name)
        elif int(count) != 0:
            failed.append(name)

    return failed


def main():
    bad_syntax = syntax_check.check(ROOT, quiet=True)
    if bad_syntax:
        syntax_check.check(ROOT)
    bad_refs = forward_refs.check(ROOT, quiet=True)
    if bad_refs:
        forward_refs.check(ROOT)

    failed = run_suites()

    say()
    say("=" * 60)
    say("syntax         %s" % ("OK" if not bad_syntax else "%d file(s) failed" % bad_syntax))
    say("forward refs   %s" % ("OK" if not bad_refs else "%d problem(s)" % bad_refs))
    if failed is None:
        say("suites         NOT RUN")
    elif failed:
        say("suites         FAILED: %s" % ", ".join(failed))
    else:
        say("suites         OK")
    say("=" * 60)

    if bad_syntax or bad_refs or failed:
        say("FAILED")
        return 1
    say("ALL CHECKS PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
