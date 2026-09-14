#!/usr/bin/env python3
"""Append fully-localized entries to Localizable.xcstrings without re-serializing it.

usage: python3 Tools/l10n_append.py path/to/Localizable.xcstrings entries.json
entries.json: {"Key": {"en": "...", "ar": "...", ...all eleven languages...}, ...}

Xcode sorts catalog keys with its own collation, so rewriting the whole file
from Python produces a diff of thousands of lines. This patches instead: an
extracted-but-empty stub (`"Key" : {},`) is replaced in place; a brand-new key
is appended at the end of "strings" in Xcode's own formatting. Xcode re-sorts
on its next save, which is a no-op for the content.
"""
import json
import sys

LANGS = ["ar", "de", "en", "es", "fr", "hi", "it", "ja", "ko", "pt-BR", "zh-Hans"]


def esc(s):
    return json.dumps(s, ensure_ascii=False)


def block(key, locs):
    lines = [f'    {esc(key)} : {{', '      "extractionState" : "manual",', '      "localizations" : {']
    for i, lang in enumerate(LANGS):
        lines += [f'        "{lang}" : {{', '          "stringUnit" : {', '            "state" : "translated",',
                  f'            "value" : {esc(locs[lang])}', '          }',
                  '        }' + (',' if i < len(LANGS) - 1 else '')]
    lines += ['      }', '    }']
    return '\n'.join(lines)


def main():
    path, entries_path = sys.argv[1], sys.argv[2]
    raw = open(path).read()
    existing = json.loads(raw)['strings']
    entries = json.load(open(entries_path))
    for key, locs in entries.items():
        missing = [l for l in LANGS if l not in locs]
        assert not missing, f"{key!r} lacks {missing}"
        assert key not in existing or not existing[key].get('localizations'), f"{key!r} already localized"
        stub = f'    {esc(key)} : {{}},'
        if stub in raw:
            raw = raw.replace(stub, block(key, locs) + ',')
        else:
            tail = '\n  },\n  "version" : "1.0"\n}\n'
            assert raw.endswith(tail), "unexpected file tail"
            raw = raw[:-len(tail)] + ',\n' + block(key, locs) + tail
    json.loads(raw)
    open(path, 'w').write(raw)
    print(f"appended {len(entries)}")


if __name__ == "__main__":
    main()
