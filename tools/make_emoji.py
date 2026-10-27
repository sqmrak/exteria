#!/usr/bin/env python3
"""writes the emoji tables and the picture pack from the Unicode emoji test file and a color emoji font

usage: make_emoji.py --test emoji-test.txt --font NotoColorEmoji.ttf --data core/emoji/exteria_emoji_data.c \
                     --pack resources/emoji/emoji.pack [--side 56] [--quality 78]

emoji-test.txt comes from https://unicode.org/Public/emoji/latest/ and the font is the iOS emoji font of
https://github.com/Keinta15/Magisk-iOS-Emoji (system/fonts/NotoColorEmoji.ttf, a CBDT font with Apple's pictures).
An emoji the font lacks keeps the picture the existing pack holds for it (the Noto 3D one for the emoji newer than the
font), so a rerun never drops a picture. Needs fonttools and pillow with webp support.

The sequence table is sorted by code points so the runtime can binary search it. A picture is kept for every fully
qualified emoji, so the app draws one set on every system and no system shows an empty box for an emoji it lacks.
Pack layout, little endian: "EXEM", u32 count, u16 side, u16 zero, then count * (u32 offset, u32 length) from the
start of the file, then the webp pictures.
"""
import argparse
import os
import re
import struct
import sys

from fontTools.ttLib import TTFont
from PIL import Image

LINE = re.compile(r"^([0-9A-F ]+?)\s*;\s*([a-z-]+)\s*#\s*\S+\s+E(\d+)\.(\d+)\s")
STATUS = {"fully-qualified": 0, "minimally-qualified": 1, "unqualified": 2}
TONES = range(0x1F3FB, 0x1F400)
GROUPS = ["Smileys & Emotion", "People & Body", "Animals & Nature", "Food & Drink", "Travel & Places",
          "Activities", "Objects", "Symbols", "Flags"]


def read_test(path):
    entries = []
    group = -1
    canonical = None
    for raw in open(path, encoding="utf-8"):
        line = raw.rstrip("\n")
        if line.startswith("# group:"):
            name = line.split(":", 1)[1].strip()
            group = GROUPS.index(name) if name in GROUPS else -1
            continue
        m = LINE.match(line)
        if not m or m.group(2) not in STATUS:
            continue
        points = tuple(int(p, 16) for p in m.group(1).split())
        status = STATUS[m.group(2)]
        version = int(m.group(3)) * 10 + int(m.group(4))
        if version > 255:
            sys.exit("emoji version does not fit a byte: " + line)
        entry = {"points": points, "status": status, "version": version, "group": max(group, 0),
                 "order": len(entries), "tone": any(p in TONES for p in points)}
        if status == 0:
            canonical = entry
        entry["canonical"] = canonical
        entries.append(entry)
    return entries


def font_pictures(path):
    """the png of every sequence a CBDT font draws, keyed by code points: single characters come from the cmap and
    sequences from the ligature lookups of GSUB"""
    font = TTFont(path)
    owner = {}
    for point, glyph in font.getBestCmap().items():
        owner.setdefault(glyph, point)
    sequences = {(point,): glyph for point, glyph in font.getBestCmap().items()}
    for lookup in font["GSUB"].table.LookupList.Lookup:
        for table in lookup.SubTable:
            if lookup.LookupType == 7:
                table = table.ExtSubTable
            for first, ligatures in getattr(table, "ligatures", {}).items():
                for ligature in ligatures:
                    parts = [first] + list(ligature.Component)
                    if all(part in owner for part in parts):
                        sequences[tuple(owner[part] for part in parts)] = ligature.LigGlyph
    bitmaps = font["CBDT"].strikeData[0]
    return {points: bitmaps[glyph].imageData for points, glyph in sequences.items() if glyph in bitmaps}


def picture_for(pictures, points):
    stripped = tuple(p for p in points if p != 0xFE0F)
    for candidate in (tuple(points), stripped):
        if candidate in pictures:
            return pictures[candidate]
    return None


def encode(data, side, quality):
    """a font bitmap is wider than tall, so it is centred on a square before it is scaled"""
    from io import BytesIO
    image = Image.open(BytesIO(data)).convert("RGBA")
    edge = max(image.size)
    square = Image.new("RGBA", (edge, edge), (0, 0, 0, 0))
    square.paste(image, ((edge - image.size[0]) // 2, (edge - image.size[1]) // 2))
    out = BytesIO()
    square.resize((side, side), Image.LANCZOS).save(out, "WEBP", quality=quality, alpha_quality=quality, method=6)
    return out.getvalue()


def read_old_pictures(data_path, pack_path):
    """the webp of every emoji the existing pack holds, keyed by code points, read before the pack is rewritten"""
    if not (os.path.exists(data_path) and os.path.exists(pack_path)):
        return {}, 0
    text = open(data_path, encoding="utf-8").read()
    pool = [int(v, 16) for v in re.search(r"exteria_emoji_points\[\d+\] = \{(.*?)\};", text, re.S).group(1).replace("\n", " ").replace(",", " ").split()]
    rows = re.search(r"exteria_emoji_entries\[\d+\] = \{(.*?)\n\};", text, re.S).group(1)
    blob = open(pack_path, "rb").read()
    magic, count, side, _ = struct.unpack_from("<4sIHH", blob)
    if magic != b"EXEM":
        sys.exit("the existing pack is not an emoji pack")
    old = {}
    for row in re.findall(r"\{([^{}]*)\}", rows):
        offset, length, _status, _version, _group, _canon, image, _tone = (int(v) for v in row.split(","))
        if image == 0xFFFF:
            continue
        start, size = struct.unpack_from("<II", blob, 12 + 8 * image)
        old[tuple(pool[offset:offset + length])] = blob[start:start + size]
    return old, side


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--test", required=True)
    ap.add_argument("--font", required=True)
    ap.add_argument("--data", required=True)
    ap.add_argument("--pack", required=True)
    ap.add_argument("--side", type=int, default=56)
    ap.add_argument("--quality", type=int, default=78)
    args = ap.parse_args()

    entries = read_test(args.test)
    if len({e["points"] for e in entries}) != len(entries):
        sys.exit("the test file lists a sequence twice")
    maxlen = max(len(e["points"]) for e in entries)

    pictures = font_pictures(args.font)
    old, old_side = read_old_pictures(args.data, args.pack)
    blobs = []
    missing = []
    kept = []
    for e in entries:
        e["image"] = 0xFFFF
        if e["status"] != 0:
            continue
        data = picture_for(pictures, e["points"])
        if data:
            blob = encode(data, args.side, args.quality)
        elif e["points"] in old and old_side == args.side:
            blob = old[e["points"]]
            kept.append(e)
        else:
            missing.append(e)
            continue
        e["image"] = len(blobs)
        blobs.append(blob)
    if len(blobs) >= 0xFFFF:
        sys.exit("too many pictures for a 16 bit index")

    ordered = sorted(entries, key=lambda e: e["points"])
    index = {e["points"]: i for i, e in enumerate(ordered)}

    pool = []
    for e in ordered:
        e["offset"] = len(pool)
        pool.extend(e["points"])

    firsts = sorted({e["points"][0] for e in ordered})
    picker = [e for e in entries if e["status"] == 0 and not e["tone"]]
    group_start = []
    for g in range(len(GROUPS)):
        group_start.append(next(i for i, e in enumerate(picker) if e["group"] == g))
    group_start.append(len(picker))

    os.makedirs(os.path.dirname(args.data), exist_ok=True)
    with open(args.data, "w", encoding="utf-8") as out:
        out.write("/* generated by tools/make_emoji.py from the Unicode emoji test file, do not edit.\n")
        out.write("   Unicode data files and software, copyright Unicode, Inc., terms at https://www.unicode.org/terms_of_use.html */\n")
        out.write('#include "exteria_emoji.h"\n\n')
        out.write("const uint32_t exteria_emoji_points[%d] = {\n" % len(pool))
        for i in range(0, len(pool), 12):
            out.write("    " + ", ".join("0x%X" % p for p in pool[i:i + 12]) + ",\n")
        out.write("};\n\n")
        out.write("const exteria_emoji_entry exteria_emoji_entries[%d] = {\n" % len(ordered))
        for e in ordered:
            canon = index[e["canonical"]["points"]]
            out.write("    {%d, %d, %d, %d, %d, %d, %d, %d},\n" % (
                e["offset"], len(e["points"]), e["status"], e["version"], e["group"], canon, e["image"], 1 if e["tone"] else 0))
        out.write("};\n\n")
        out.write("const uint32_t exteria_emoji_first_points[%d] = {\n" % len(firsts))
        for i in range(0, len(firsts), 12):
            out.write("    " + ", ".join("0x%X" % p for p in firsts[i:i + 12]) + ",\n")
        out.write("};\n\n")
        out.write("const uint16_t exteria_emoji_picker[%d] = {\n" % len(picker))
        for i in range(0, len(picker), 16):
            out.write("    " + ", ".join(str(index[e["points"]]) for e in picker[i:i + 16]) + ",\n")
        out.write("};\n\n")
        out.write("const uint16_t exteria_emoji_group_start[%d] = {%s};\n\n" % (len(GROUPS) + 1, ", ".join(map(str, group_start))))
        out.write("const size_t exteria_emoji_entry_count = %d;\n" % len(ordered))
        out.write("const size_t exteria_emoji_first_count = %d;\n" % len(firsts))
        out.write("const size_t exteria_emoji_picker_count = %d;\n" % len(picker))
        out.write("const size_t exteria_emoji_image_count = %d;\n" % len(blobs))
        out.write("const size_t exteria_emoji_longest = %d;\n" % maxlen)

    os.makedirs(os.path.dirname(args.pack), exist_ok=True)
    header = 12 + 8 * len(blobs)
    with open(args.pack, "wb") as out:
        out.write(b"EXEM" + struct.pack("<IHH", len(blobs), args.side, 0))
        offset = header
        for blob in blobs:
            out.write(struct.pack("<II", offset, len(blob)))
            offset += len(blob)
        for blob in blobs:
            out.write(blob)

    total = sum(len(b) for b in blobs)
    print("entries %d (longest %d code points), pictures %d, %d bytes, average %d" % (len(ordered), maxlen, len(blobs), total, total // max(1, len(blobs))))
    print("picker %d, groups %s" % (len(picker), group_start))
    if kept:
        print("kept the picture of the existing pack for %d emoji the font lacks, newest first:" % len(kept))
        for e in sorted(kept, key=lambda e: -e["version"])[:4]:
            print("  E%.1f %s" % (e["version"] / 10.0, " ".join("%X" % p for p in e["points"])))
    if missing:
        print("no picture for %d emoji, newest first:" % len(missing))
        for e in sorted(missing, key=lambda e: -e["version"])[:8]:
            print("  E%.1f %s" % (e["version"] / 10.0, " ".join("%X" % p for p in e["points"])))


if __name__ == "__main__":
    main()
