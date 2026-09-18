#!/usr/bin/env python3
"""Resolve a String Catalog merge conflict semantically.

Xcode re-sorts and re-serialises `Localizable.xcstrings` whenever it saves it,
so two branches that each touched the catalog conflict on almost every line
even when they added disjoint keys. Git cannot see that; this can.

Usage, from inside a conflicted merge:

    python3 Tools/merge_localizable.py Caroullage/Resources/Localizable.xcstrings
    git add Caroullage/Resources/Localizable.xcstrings

It reads the three sides from the index (base, ours, theirs), keeps OUR
ordering and serialisation, and adds every key that only THEIRS has, in the
position our ordering would put it. A key both sides changed keeps our
version, and the script says so. It can also be run on three explicit files:

    python3 Tools/merge_localizable.py --ours ours.json --theirs theirs.json --out merged.json
"""
import argparse
import collections
import json
import subprocess
import sys


def load(text):
    return json.loads(text, object_pairs_hook=collections.OrderedDict)


def dump(catalog):
    return json.dumps(catalog, ensure_ascii=False, indent=2, separators=(",", " : ")) + "\n"


def fold(key):
    return key.casefold()


def merge(ours, theirs, base=None):
    strings = collections.OrderedDict(ours["strings"])
    added, kept_ours = [], []
    for key, entry in theirs["strings"].items():
        if key not in strings:
            keys = list(strings.keys())
            position = 0
            for index, existing in enumerate(keys):
                if fold(existing) < fold(key):
                    position = index + 1
                else:
                    break
            items = list(strings.items())
            items.insert(position, (key, entry))
            strings = collections.OrderedDict(items)
            added.append(key)
        elif strings[key] != entry:
            base_entry = (base or {}).get("strings", {}).get(key)
            if base_entry is not None and entry == base_entry:
                continue                      # only ours changed it: ours stands
            if base_entry is not None and strings[key] == base_entry:
                strings[key] = entry          # only theirs changed it: take theirs
            else:
                kept_ours.append(key)         # both changed it: ours wins, and we say so
    merged = collections.OrderedDict(ours)
    merged["strings"] = strings
    return merged, added, kept_ours


def from_index(path):
    def stage(n):
        result = subprocess.run(["git", "show", f":{n}:{path}"], capture_output=True, text=True)
        if result.returncode != 0:
            sys.exit(f"{path} is not in a merge conflict (no stage {n} in the index); nothing to do.")
        return result.stdout
    return load(stage(1)), load(stage(2)), load(stage(3))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("path", nargs="?", help="the conflicted catalog path (reads base/ours/theirs from the index)")
    parser.add_argument("--ours")
    parser.add_argument("--theirs")
    parser.add_argument("--base")
    parser.add_argument("--out")
    args = parser.parse_args()

    if args.path:
        base, ours, theirs = from_index(args.path)
        out = args.out or args.path
    elif args.ours and args.theirs:
        ours = load(open(args.ours).read())
        theirs = load(open(args.theirs).read())
        base = load(open(args.base).read()) if args.base else None
        out = args.out or args.ours
    else:
        parser.error("give a conflicted path, or --ours and --theirs")

    merged, added, kept = merge(ours, theirs, base)
    with open(out, "w") as handle:
        handle.write(dump(merged))
    print(f"wrote {out}: {len(merged['strings'])} keys, {len(added)} added from theirs")
    if kept:
        print("both sides changed these; OURS kept — check them:", ", ".join(kept), file=sys.stderr)


if __name__ == "__main__":
    main()
