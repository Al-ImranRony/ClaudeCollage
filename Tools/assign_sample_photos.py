#!/usr/bin/env python3
"""Re-dresses every collage template's sample photos from the expanded pool.

usage: python3 Tools/assign_sample_photos.py <repo root> <out.json> [--carousels]
Without --carousels it dresses collage templates; with it, carousel templates
(their `framePhotos`). Then write out.json into SampleContent/sample_content_manifest.json's
"templates" (one line per id) and bump its "version". Add a new template's
theme to NEW (or LEGACY by category) first; tags come from the filename,
e.g. sample_cafe_03 -> TAGS["cafe"].

Greedy, in visibility order (spotlight → shelves → the rest). For each photo
slot it picks the lowest-cost photo where cost = reuse + same-shelf repeat +
theme mismatch + orientation mismatch. Never repeats a photo within a template.
"""
import json, glob, math, os, subprocess, sys, collections, zlib

ROOT = sys.argv[1]
RES = os.path.join(ROOT, "Caroullage/Resources")
SIZES = {"1:1": (1080, 1080), "4:5": (1080, 1350), "9:16": (1080, 1920), "16:9": (1920, 1080)}

TAGS = {
    "portrait": {"woman", "portrait"}, "style": {"woman", "portrait", "style"},
    "man": {"man", "portrait"}, "couple": {"couple"}, "friends": {"friends"},
    "family": {"family"}, "food": {"food", "dish"}, "cafe": {"food", "cafe"},
    "travel": {"travel", "beach"}, "nature": {"travel", "nature"}, "road": {"travel", "road"},
    "city": {"city", "travel"}, "seasonal": {"autumn", "portrait"}, "holiday": {"holiday"},
    "gathering": {"holiday", "friends", "gathering"}, "cozy": {"holiday", "cozy"},
    "party": {"party", "friends"}, "flowers": {"flowers"}, "pet": {"pet"}, "vintage": {"vintage"},
}

photos = {}
for path in sorted(glob.glob(os.path.join(RES, "SampleContent/sample_*.jpg"))):
    name = os.path.basename(path)[:-4]
    if "loop" in name:
        continue
    kind = name.split("_")[1]
    out = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", path],
                         capture_output=True, text=True).stdout.split()
    w, h = int(out[-3]), int(out[-1])
    photos[name] = {"tags": TAGS[kind], "aspect": w / h}

templates = {}
for path in glob.glob(os.path.join(RES, "Templates/*.json")):
    if path.endswith("template_schema.json"):
        continue
    t = json.load(open(path))
    templates[t["id"]] = t

NEW = {
    "instant-solo": ["portrait"], "instant-trio": ["beach", "beach", "couple"],
    "instant-booth": ["friends", "party", "couple", "man"],
    "instant-taped": ["family", "food", "pet", "flowers"],
    "film-contact-roll": ["travel", "portrait", "city"],
    "film-strip-story": ["couple", "road", "cafe", "portrait"],
    "film-negative-duo": ["woman", "man"],
    "editorial-issue": ["style", "city", "cafe"], "editorial-cover": ["portrait"],
    "editorial-the-edit": ["style", "cafe", "city"], "editorial-before-after": ["food", "food"],
    "dump-nine": ["friends", "food", "travel", "portrait", "pet", "cafe", "city", "flowers", "party"],
    "dump-moodboard": ["style", "flowers", "cafe", "nature", "vintage", "city"],
    "dump-weekend-recap": ["friends", "cafe", "road", "couple", "man", "party"],
    "dump-year-in-frames": ["travel", "family", "party", "couple", "holiday", "pet"],
    "grid-soft-four": ["portrait", "flowers", "cafe", "couple"],
    "grid-airy-nine": ["portrait", "travel", "food", "man", "flowers", "city", "family", "pet", "friends"],
    "grid-rounded-trio": ["nature", "cafe", "portrait"],
    "minimal-bubbles": ["portrait", "cafe", "flowers", "pet"],
    "minimal-cameo": ["woman", "family", "family"], "minimal-white-space": ["travel", "couple"],
    "story-day-in-my-life": ["portrait", "cafe", "city", "friends"],
    "seasonal-cozy": ["holiday", "cozy", "gathering"],
    "seasonal-holiday-booth": ["holiday", "gathering", "cozy"],
    "seasonal-friendsgiving": ["gathering", "food", "gathering", "friends"],
    "travel-boarding-pass": ["travel", "couple"],
}
LEGACY = {
    "grid": ["portrait", "travel", "food", "couple", "man", "friends"],
    "minimal": ["portrait", "flowers", "man", "couple"],
    "story": ["portrait", "city", "friends", "couple", "man"],
    "travel": ["travel", "nature", "road", "city", "couple"],
    "seasonal": ["autumn", "holiday", "family", "cozy"],
    "birthday": ["party", "friends"],
}
OVERRIDES = {"seasonal-thanks": ["gathering", "food"], "seasonal-greeting": ["holiday", "cozy"],
             "seasonal-ornament": ["holiday", "family", "cozy", "gathering", "holiday"],
             "seasonal-sparkle": ["holiday"], "grid-celebrate": ["party", "friends"],
             "seasonal-bloom": ["flowers", "family", "flowers"], "minimal-circle-focus": ["portrait", "man"]}

# Templates whose headline names an occasion: an off-theme photo under
# "Happy Holidays" is worse than a repeat on the same shelf.
STRICT = {"seasonal-greeting", "seasonal-sparkle", "seasonal-thanks", "seasonal-friendsgiving",
          "seasonal-holiday-booth", "seasonal-cozy", "seasonal-ornament", "birthday-bash",
          "birthday-confetti", "grid-celebrate", "editorial-before-after"}

def wants(tid):
    if tid in NEW: return NEW[tid]
    if tid in OVERRIDES: return OVERRIDES[tid]
    return LEGACY.get(templates[tid]["category"], ["portrait", "travel"])

curation = json.load(open(os.path.join(RES, "Collections/collage_gallery.json")))
groups = [("spotlight", curation["spotlight"])]
order_cat = {}
for shelf in curation["shelves"]:
    ids = shelf.get("templateIDs") or sorted(
        [t for t in templates if templates[t]["category"] == shelf.get("category")],
        key=lambda t: (t not in curation["newTemplateIDs"],
                       curation["newTemplateIDs"].index(t) if t in curation["newTemplateIDs"] else 0, t))
    groups.append((shelf["id"], ids[:12]))
membership = collections.defaultdict(set)
for gid, ids in groups:
    for t in ids: membership[t].add(gid)

order, seen = [], set()
for _, ids in groups:
    for t in ids:
        if t in templates and t not in seen: order.append(t); seen.add(t)
order += sorted(t for t in templates if t not in seen)

uses = collections.Counter()
group_used = collections.defaultdict(set)
CAROUSELS = len(sys.argv) > 3 and sys.argv[3] == "--carousels"

def cost_of(name, p, pref, union, strict, cell_aspect):
    if pref in p["tags"] or pref == name.split("_")[1]: theme = 0
    elif p["tags"] & union: theme = 30 if strict else 7
    else: theme = 70 if strict else 35
    return theme + 5 * abs(math.log(cell_aspect / p["aspect"])) \
        + (zlib.crc32(name.encode()) % 100) / 1000

result = {}
for tid in ([] if CAROUSELS else order):
    t = templates[tid]
    W, H = SIZES[t["canvasAspectRatio"]]
    prefs = wants(tid)
    union = set().union(*(TAGS.get(p, {p}) for p in prefs)) | set(prefs)
    chosen = []
    for i, cell in enumerate(c for c in t["cells"] if c["type"] == "photo"):
        f = cell["frame"]
        cell_aspect = (f["width"] * W) / max(f["height"] * H, 1)
        pref = prefs[i % len(prefs)]
        best = None
        for name, p in photos.items():
            if name in chosen: continue
            cost = 10 * uses[name]
            if any(name in group_used[g] for g in membership[tid]): cost += 40
            if pref in p["tags"] or pref == name.split("_")[1]: cost += 0
            elif p["tags"] & union: cost += 7
            else: cost += 70 if tid in STRICT else 18
            cost += 5 * abs(math.log(cell_aspect / p["aspect"]))
            cost += (zlib.crc32((name + tid).encode()) % 100) / 1000  # stable tie-break within a run
            if best is None or cost < best[0]: best = (cost, name)
        chosen.append(best[1])
        uses[best[1]] += 1
        for g in membership[tid]: group_used[g].add(best[1])
    result[tid] = chosen

if CAROUSELS:
    # --- Carousel templates -------------------------------------------------
    # Captions decide themes ("Meet the Team" names four women; "Menu Cards"
    # is food). Grid Reveal repeats its grid's photos one per later slide BY
    # DESIGN, so only slide 1 is chosen and the rest mirror it. A panorama
    # slices ONE wide photo across every slide; those few wide sources are
    # picked by hand below.
    manifest = json.load(open(os.path.join(RES, "SampleContent/sample_content_manifest.json")))
    collage_uses = collections.Counter(p for v in manifest["templates"].values() for p in v["photos"])
    CAR = {
        "carousel-matched-team": (["woman"], True), "carousel-matched-menu": (["dish", "dish", "dish", "cafe"], True),
        "carousel-matched-tips": (["portrait", "man", "style"], False),
        "carousel-matched-steps": (["cafe", "flowers", "vintage", "cozy", "food"], False),
        "carousel-matched-product": (["vintage", "cafe", "flowers", "cozy"], True),
        "carousel-matched-quotes": (["nature", "flowers", "city"], False),
        "carousel-matched-contactsheet": (["travel", "portrait", "friends", "city", "food", "family"], False),
        "carousel-matched-filmframes": (["travel", "city", "road", "couple", "friends"], False),
        "carousel-matched-framedmoments": (["portrait", "man", "couple", "family", "friends", "pet"], False),
        "carousel-matched-gallerywall": (["travel", "couple", "nature", "city", "flowers"], False),
        "carousel-matched-photodump": (["friends", "food", "travel", "portrait", "pet", "cafe", "city", "flowers", "party", "man"], False),
        "carousel-matched-softfocus": (["portrait", "flowers", "couple"], False),
        "carousel-matched-cleantrio": (["portrait", "travel", "food", "man", "flowers", "city", "family", "couple"], False),
        "carousel-story-beforeafter": (["food", "food"], True),
        "carousel-story-editorial": (["travel", "couple", "nature", "cafe", "friends"], False),
        "carousel-story-lessons": (["portrait", "man", "style"], False),
        "carousel-story-recipe": (["dish", "cafe", "cozy", "gathering"], True),
        "carousel-story-travel": (["travel", "nature", "road", "city"], True),
        "carousel-story-tutorial": (["style", "portrait", "flowers"], False),
        "carousel-gridpreview-4cell": (["friends", "party"], True),
        "carousel-gridpreview-6cell": (["portrait", "man"], False),
        "carousel-gridpreview-family": (["family"], True),
        "carousel-gridpreview-travel": (["travel", "nature", "road", "city"], True),
    }
    PANORAMA = {"carousel-panoramic-beach": "sample_travel_03", "carousel-panoramic-city": "sample_city_05",
                "carousel-panoramic-skyline": "sample_travel_04", "carousel-panoramic-sunset": "sample_road_03",
                "carousel-panoramic-travel": "sample_road_04"}

    ctemplates = {}
    for path in glob.glob(os.path.join(RES, "CarouselTemplates/*.json")):
        t = json.load(open(path))
        if "id" in t: ctemplates[t["id"]] = t
    featured = [c for c in manifest.get("featuredCarousels", []) if c in ctemplates]
    # Theme-critical carousels (captions name the subject) pick first, so a
    # mixed photo dump cannot take the only dishes before "Menu Cards" asks.
    base = featured + sorted(c for c in ctemplates if c not in featured)
    corder = [c for c in base if CAR.get(c, ([], False))[1]] + \
             [c for c in base if not CAR.get(c, ([], False))[1]]

    tab_uses, covers, section_used = collections.Counter(), set(), collections.defaultdict(set)
    for tid, pano in PANORAMA.items():
        tab_uses[pano] += 1; covers.add(pano); section_used["panoramic"].add(pano)
    out = {}
    for tid in corder:
        t = ctemplates[tid]
        frames = sorted(t["frames"], key=lambda f: f.get("index", 0))
        if tid in PANORAMA:
            out[tid] = [[PANORAMA[tid]] for _ in frames]
            continue
        W, H = SIZES[t["canvasAspectRatio"]]
        prefs, strict = CAR[tid]
        # Literal: "cozy" must not admit every holiday photo through its tags.
        union = set(prefs)
        section = t.get("carouselType", "")
        mirror = section == "gridPreview"
        chosen, slides, slot = [], [], 0
        for fi, frame in enumerate(frames):
            cells = [c for c in frame["cells"] if c["type"] == "photo"]
            if mirror and fi > 0:
                slides.append([slides[0][fi - 1]] if fi - 1 < len(slides[0]) else [slides[0][-1]])
                continue
            picks = []
            for ci, cell in enumerate(cells):
                f = cell["frame"]
                cell_aspect = (f["width"] * W) / max(f["height"] * H, 1)
                pref = prefs[slot % len(prefs)]; slot += 1
                is_cover = fi == 0 and ci == 0
                best = None
                for name, p in photos.items():
                    if name in chosen: continue
                    c = 10 * tab_uses[name] + 2 * collage_uses[name]
                    if is_cover and name in covers: c += 60
                    # A repeat within the type section is cheaper than an
                    # off-theme slide: "5 Quick Tips" over Christmas trees
                    # reads as a broken template, a familiar face does not.
                    if name in section_used[section]: c += 15
                    if "holiday" in p["tags"] and not union & {"holiday", "cozy", "gathering"}:
                        c += 60   # out-of-season photos stay in holiday carousels
                    c += cost_of(name, p, pref, union, strict, cell_aspect)
                    if best is None or c < best[0]: best = (c, name)
                name = best[1]
                chosen.append(name); picks.append(name)
                tab_uses[name] += 1; section_used[section].add(name)
                if is_cover: covers.add(name)
            slides.append(picks)
        out[tid] = slides

    slots = sum(tab_uses.values())
    print("carousel slots (distinct per carousel)", slots, "photos used", len(tab_uses),
          "max reuse", max(tab_uses.values()), "mean %.2f" % (slots / len(tab_uses)))
    json.dump(out, open(sys.argv[2], "w"), indent=1)
    sys.exit(0)

print("slots", sum(uses.values()), "photos used", len(uses), "of", len(photos),
      "max reuse", max(uses.values()), "mean %.2f" % (sum(uses.values()) / len(uses)))
print("unused:", sorted(set(photos) - set(uses)))
json.dump(result, open(sys.argv[2], "w"), indent=1)
