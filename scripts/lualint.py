"""Cheap Lua sanity check without a Lua interpreter.

Catches the two classes of error we already tripped over:

  1. obj:Method not followed by arguments -- Lua requires a call right after
     the colon (`b:GetEffectiveAlpha and ...` does not compile);
  2. a line starting with '(' or '[' -- Lua 5.1 glues it to the previous
     expression: "ambiguous syntax".

Plus unterminated string literals, and unknown escapes in strings: Lua 5.1
turns "\\D" into plain "D", so a texture path written with single backslashes
("Interface\\Icons\\X") silently breaks. Long strings [==[ ... ]==] are skipped. ASCII-only output: the Windows console
here is cp866 and mangles Cyrillic.
"""

import io
import re
import sys

LONG_OPEN = re.compile(r"(?<!-)\[(=*)\[")
CALL = re.compile(r""":([A-Za-z_]\w*)\b(?![ \t]*[('"{\[])""")


VALID_ESCAPES = set("abfnrtv\\\"'0123456789")


def strip(line, bad_escapes=None):
    """Drop comments and string-literal contents; collect unknown escapes."""
    out, i, quote = [], 0, None
    while i < len(line):
        c = line[i]
        if quote:
            if c == "\\":
                following = line[i + 1:i + 2]
                if following and following not in VALID_ESCAPES and bad_escapes is not None:
                    bad_escapes.append("\\" + following)
                i += 2
                continue
            if c == quote:
                quote = None
            i += 1
            continue
        if c in "\"'":
            quote = c
            i += 1
            continue
        if line.startswith("--", i):
            break
        out.append(c)
        i += 1
    return "".join(out), quote is not None


def check(path):
    bad = []
    depth = 0          # open brackets: inside a constructor or call arg list
    long_close = None  # "]==]" while inside a long string [==[ ... ]==]
    for n, raw in enumerate(io.open(path, encoding="utf-8").read().splitlines(), 1):
        # Long strings (JSON in lang/*.lua) are data, not code: skip their body.
        if long_close:
            end = raw.find(long_close)
            if end < 0:
                continue
            raw = raw[end + len(long_close):]
            long_close = None
        opening = LONG_OPEN.search(raw)
        if opening and not opening.group(0).startswith("--"):
            close = "]" + opening.group(1) + "]"
            rest = raw[opening.end():]
            if close not in rest:
                long_close = close
                raw = raw[:opening.start()] + '""'
        bad_escapes = []
        code, unterminated = strip(raw, bad_escapes)
        if unterminated:
            bad.append((n, "unterminated string", raw.strip()))
        for escape in bad_escapes:
            bad.append((n, "unknown escape %s in a string (use \\\\ for a backslash)" % escape, raw.strip()))

        # A line may start with '[' or '(' only when it continues something:
        # a table key inside { }, an argument inside ( ). At depth 0 it is a
        # new statement, and Lua 5.1 glues it to the previous one.
        if depth == 0 and code.lstrip()[:1] in ("(", "["):
            bad.append((n, "line starts with a bracket (ambiguous syntax)", raw.strip()))
        for m in CALL.finditer(code):
            bad.append((n, f"method call :{m.group(1)} without arguments", raw.strip()))

        depth += code.count("{") + code.count("(") + code.count("[")
        depth -= code.count("}") + code.count(")") + code.count("]")
        if depth < 0:
            depth = 0
    return bad


rc = 0
for path in sys.argv[1:]:
    bad = check(path)
    name = path.replace("\\", "/").split("/")[-1]
    print(f"{name}: {'ok' if not bad else str(len(bad)) + ' issues'}")
    for n, why, text in bad:
        rc = 1
        print(f"  {n}: {why}")
sys.exit(rc)
