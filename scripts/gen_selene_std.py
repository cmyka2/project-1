#!/usr/bin/env python3
"""Builds roblox.yml for Selene when Roblox's CDN is unreachable.

Combines Selene's roblox_base.yml with the globals and enums that
`selene generate-roblox-std` would normally add, using the public
API dump mirrored by MaximumADHD/Roblox-Client-Tracker.
Usage: python3 scripts/gen_selene_std.py .tools/roblox_base.yml .tools/API-Dump.json > roblox.yml
"""
import json
import sys

base_path, dump_path = sys.argv[1], sys.argv[2]
base = open(base_path, encoding="utf-8").read().rstrip() + "\n"
dump = json.load(open(dump_path, encoding="utf-8"))

globals_extra = []
for name in ("game", "script", "workspace", "plugin"):
    globals_extra.append(f"  {name}:\n    struct: AnyStruct\n")
for enum in sorted(e["Name"] for e in dump.get("Enums", [])):
    globals_extra.append(f"  Enum.{enum}:\n    struct: AnyStruct\n")
structs_extra = '  AnyStruct:\n    "*":\n      any: true\n'

head, sep, tail = base.partition("\nstructs:\n")
if not sep:
    raise SystemExit("unexpected base format: no structs section")
sys.stdout.write(head + "\n" + "".join(globals_extra) + "structs:\n" + structs_extra + tail)
