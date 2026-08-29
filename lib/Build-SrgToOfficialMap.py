#!/usr/bin/env python3
"""Build srg (m_123_ / f_123_) -> Mojang official simple name for MC 1.20.1."""
from __future__ import annotations

import json
import re
from collections import defaultdict
from pathlib import Path

# Prefer workstation Minecraft_Mappings 1.20.1 flat export (0 conflicts / 0 unresolved).
FLAT = Path(r"F:\rob_projects\Minecraft_AI_Workstation\knowledge\Minecraft_Mappings\1.20.1\generated\SRG_TO_MOJANG_1.20.1.flat.tsv")
TSRG = Path(r"F:\rob_projects\Minecraft_AI_Workstation\knowledge\1.20.1_mcp_mappng\mcp_config-1.20.1-20230612.114412\config\joined.tsrg")
MOJ = Path(r"F:\rob_projects\Minecraft_AI_Workstation\knowledge\minecraft_java\versions\1.20.1\client_mappings.txt")
OUT = Path(__file__).with_name("Srg1201Official.json")

SRG_RE = re.compile(r"^[fm]_\d+_$")
MOJ_CLASS = re.compile(r"^(\S+) -> (\S+):$")
MOJ_FIELD = re.compile(r"^\s+(\S+) (\S+) -> (\S+)$")
MOJ_METHOD = re.compile(r"^\s+(?:\d+:\d+:)?(\S+) (\S+)\((.*)\) -> (\S+)$")

PRIM = {
    "void": "V",
    "boolean": "Z",
    "byte": "B",
    "char": "C",
    "short": "S",
    "int": "I",
    "long": "J",
    "float": "F",
    "double": "D",
}


def java_type_to_desc(t: str) -> str:
    t = t.strip()
    if not t:
        return ""
    arr = 0
    while t.endswith("[]"):
        arr += 1
        t = t[:-2].strip()
    if t in PRIM:
        d = PRIM[t]
    else:
        d = "L" + t.replace(".", "/") + ";"
    return "[" * arr + d


def java_args_to_desc(args: str) -> str:
    args = args.strip()
    if not args:
        return "()"
    parts = []
    depth = 0
    cur = []
    for ch in args:
        if ch == "<":
            depth += 1
            continue
        if ch == ">":
            depth -= 1
            continue
        if ch == "," and depth == 0:
            parts.append("".join(cur).strip())
            cur = []
            continue
        if depth == 0:
            cur.append(ch)
    if cur:
        parts.append("".join(cur).strip())
    # drop generics leftovers and annotations
    cleaned = []
    for p in parts:
        p = p.replace("...", "[]").strip()
        if not p:
            continue
        cleaned.append(java_type_to_desc(p))
    return "(" + "".join(cleaned) + ")"


def parse_mojang(path: Path):
    fields: dict[tuple[str, str], str] = {}
    methods: dict[tuple[str, str, str], str] = {}
    methods_by_name: dict[tuple[str, str], set[str]] = defaultdict(set)
    cur_obf = None
    with path.open(encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            cm = MOJ_CLASS.match(line)
            if cm:
                cur_obf = cm.group(2)
                continue
            if cur_obf is None:
                continue
            mm = MOJ_METHOD.match(line)
            if mm:
                ret, name, args, obf = mm.group(1), mm.group(2), mm.group(3), mm.group(4)
                if name in ("<init>", "<clinit>"):
                    continue
                desc = java_args_to_desc(args) + java_type_to_desc(ret)
                methods[(cur_obf, obf, desc)] = name
                methods_by_name[(cur_obf, obf)].add(name)
                continue
            fm = MOJ_FIELD.match(line)
            if fm and "(" not in line:
                _typ, name, obf = fm.group(1), fm.group(2), fm.group(3)
                if name not in ("<init>", "<clinit>"):
                    fields[(cur_obf, obf)] = name
    return fields, methods, methods_by_name


def parse_tsrg(path: Path):
    cur_obf_class = None
    with path.open(encoding="utf-8", errors="replace") as f:
        for line in f:
            if line.startswith("tsrg2") or not line.strip():
                continue
            if line.startswith("\t\t"):
                continue
            if line.startswith("\t"):
                if cur_obf_class is None:
                    continue
                parts = line.strip().split()
                if len(parts) < 2 or parts[0] == "static":
                    continue
                if len(parts) >= 3 and parts[1].startswith("("):
                    yield "m", parts[2], cur_obf_class, parts[0], parts[1]
                else:
                    yield "f", parts[1], cur_obf_class, parts[0], ""
            else:
                cur_obf_class = line.split()[0]


def main() -> int:
    if FLAT.is_file():
        print(f"Using workstation flat map {FLAT}")
        out: dict[str, str] = {}
        with FLAT.open(encoding="utf-8") as f:
            next(f, None)
            for line in f:
                parts = line.rstrip("\n").split("\t")
                if len(parts) >= 3:
                    out[parts[1]] = parts[2]
        OUT.write_text(json.dumps(out, indent=0, sort_keys=True), encoding="utf-8")
        print(f"Wrote {OUT} unique={len(out)}")
        return 0

    print("Parsing Mojang mappings...")
    fields, methods, methods_by_name = parse_mojang(MOJ)
    print(f"  fields={len(fields)} methods={len(methods)}")

    print("Parsing TSRG and composing...")
    out: dict[str, str] = {}
    srg_names: dict[str, set[str]] = defaultdict(set)
    mapped_m = mapped_f = miss_m = miss_f = 0
    for kind, srg, obf_cls, obf_mem, desc in parse_tsrg(TSRG):
        if not SRG_RE.match(srg):
            continue
        if kind == "f":
            name = fields.get((obf_cls, obf_mem))
            if name:
                srg_names[srg].add(name)
                mapped_f += 1
            else:
                miss_f += 1
        else:
            name = methods.get((obf_cls, obf_mem, desc))
            if not name:
                cand = methods_by_name.get((obf_cls, obf_mem))
                if cand and len(cand) == 1:
                    name = next(iter(cand))
            if name:
                srg_names[srg].add(name)
                mapped_m += 1
            else:
                miss_m += 1

    conflicts = 0
    for srg, names in srg_names.items():
        if len(names) == 1:
            out[srg] = next(iter(names))
        else:
            conflicts += 1

    print(f"  mapped methods={mapped_m} miss={miss_m}")
    print(f"  mapped fields={mapped_f} miss={miss_f}")
    print(f"  unique srg={len(out)} conflicts={conflicts}")
    OUT.write_text(json.dumps(out, indent=0, sort_keys=True), encoding="utf-8")
    print(f"Wrote {OUT} ({OUT.stat().st_size} bytes)")
    # sanity
    for k in ("m_9236_", "m_6443_", "m_122434_", "m_49635_", "m_278183_", "m_171576_", "m_171423_"):
        print(f"  {k} -> {out.get(k, 'MISSING')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
