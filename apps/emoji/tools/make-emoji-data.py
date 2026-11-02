#!/usr/bin/env python3
# Dane panelu emoji: emoji-test.txt (Unicode) + polskie nazwy i słowa kluczowe z CLDR (pakiety
# unicode-emoji i cldr-emoji-annotation). Wynik: data/emoji.json — wbudowany w program.
#   python3 tools/make-emoji-data.py > data/emoji.json
import json, re, sys
import xml.etree.ElementTree as ET

TEST = "/usr/share/unicode/emoji/emoji-test.txt"
ANN = ["/usr/share/unicode/cldr/common/annotations/pl.xml", "/usr/share/unicode/cldr/common/annotationsDerived/pl.xml"]
GROUPS = {
    "Smileys & Emotion": ("smileys", "Buźki i emocje"),
    "People & Body": ("people", "Ludzie"),
    "Animals & Nature": ("nature", "Zwierzęta i przyroda"),
    "Food & Drink": ("food", "Jedzenie i picie"),
    "Travel & Places": ("travel", "Podróże i miejsca"),
    "Activities": ("activities", "Aktywności"),
    "Objects": ("objects", "Przedmioty"),
    "Symbols": ("symbols", "Symbole"),
    "Flags": ("flags", "Flagi"),
}
TONES = ["\U0001F3FB", "\U0001F3FC", "\U0001F3FD", "\U0001F3FE", "\U0001F3FF"]

def key(s):
    return s.replace("️", "")

names, words = {}, {}
for path in ANN:
    for a in ET.parse(path).getroot().iter("annotation"):
        cp = key(a.get("cp"))
        if a.get("type") == "tts":
            names.setdefault(cp, a.text)
        else:
            words.setdefault(cp, a.text.replace(" | ", " "))

groups, order, tones = [], {}, {}
group = None
for line in open(TEST, encoding="utf-8"):
    if line.startswith("# group:"):
        g = line.split(":", 1)[1].strip()
        group = None
        if g in GROUPS:
            gid, gname = GROUPS[g]
            group = {"id": gid, "name": gname, "emoji": []}
            groups.append(group)
        continue
    m = re.match(r"^([0-9A-F ]+);\s*fully-qualified\s*#\s*(\S+)", line)
    if not m or group is None:
        continue
    e = "".join(chr(int(c, 16)) for c in m.group(1).split())
    mods = [c for c in e if c in TONES]
    if mods:
        # Odcień skóry: tylko warianty z jednym odcieniem (ten sam dla wszystkich osób)
        if len(set(mods)) == 1:
            base = key("".join(c for c in e if c not in TONES))
            tones.setdefault(base, {})[mods[0]] = e
        continue
    k = key(e)
    name = names.get(k)
    if not name:
        continue
    item = [e, name, words.get(k, "")]
    order[k] = item
    group["emoji"].append(item)

for base, t in tones.items():
    if base in order and len(t) == 5:
        order[base].append([t[x] for x in TONES])

json.dump(groups, sys.stdout, ensure_ascii=False, separators=(",", ":"))
