#!/usr/bin/env python3
"""reads .tl schemas and writes the constructor tables used by core/tl

usage: tlgen.py --out core/tl/generated schemas/api.tl schemas/mtproto.tl ...

every explicit constructor id is checked against the crc32 of its normalized
line. a line may end with `// crc-line: <original line>` when this schema renames a
constructor that kept its name across layers, the id is then checked against that line.
`// crc-skip: <reason>` keeps an id that is known from a working client but whose published
line could not be reproduced, the tool lists these so they stay visible.
"""
import argparse
import binascii
import os
import re
import sys

BUILTIN = {
    "int": "INT", "long": "LONG", "double": "DOUBLE", "string": "STRING",
    "bytes": "BYTES", "int128": "INT128", "int256": "INT256",
}

KINDS = ["INT", "LONG", "DOUBLE", "INT128", "INT256", "STRING", "BYTES", "TRUE",
         "FLAGS", "OBJECT", "VECTOR", "GENERIC"]


class SchemaError(Exception):
    pass


def strip_comments(text):
    out = []
    layer = None
    for line in text.split("\n"):
        m = re.match(r"\s*//\s*LAYER\s+(\d+)", line)
        if m:
            layer = int(m.group(1))
        pos = line.find("//")
        crc_line = None
        if pos >= 0:
            m = re.search(r"crc-line:\s*(.*)$", line[pos:])
            if m:
                crc_line = m.group(1).strip().rstrip(";")
            m = re.search(r"crc-skip:\s*(.*)$", line[pos:])
            if m:
                crc_line = "skip:" + m.group(1).strip()
            line = line[:pos]
        out.append((line, crc_line))
    return out, layer


def parse_statements(text):
    lines, layer = strip_comments(text)
    functions = False
    stmts = []
    buf = ""
    crc_line = None
    for line, cl in lines:
        stripped = line.strip()
        if stripped == "---functions---":
            functions = True
            continue
        if stripped == "---types---":
            functions = False
            continue
        if not stripped:
            continue
        buf += " " + stripped
        if cl:
            crc_line = cl
        while ";" in buf:
            stmt, buf = buf.split(";", 1)
            stmts.append((stmt.strip(), functions, crc_line))
            crc_line = None
    if buf.strip():
        raise SchemaError("statement without a semicolon: " + buf.strip()[:80])
    return stmts, layer


class Type:

    def __init__(self, kind, name=None, bare=False, elem=None, by_ctor=False):
        self.kind = kind
        self.name = name
        self.bare = bare
        self.elem = elem
        # forward constructor references cannot be resolved until all declarations are read
        self.by_ctor = by_ctor

    def key(self):
        return (self.kind, self.name, self.bare, self.elem.key() if self.elem else None)


def split_args(s):
    parts, depth, cur = [], 0, ""
    for ch in s:
        if ch == "<":
            depth += 1
        elif ch == ">":
            depth -= 1
        if ch == " " and depth == 0:
            if cur:
                parts.append(cur)
            cur = ""
        else:
            cur += ch
    if cur:
        parts.append(cur)
    return parts


def parse_type(expr, generics):
    if expr == "#":
        return Type("FLAGS")
    if expr.startswith("!"):
        return Type("GENERIC")
    if expr in generics:
        return Type("GENERIC")
    m = re.match(r"^([Vv]ector)<(.+)>$", expr)
    if m:
        elem = parse_type(m.group(2), generics)
        return Type("VECTOR", bare=(m.group(1) == "vector"), elem=elem)
    if expr in BUILTIN:
        return Type(BUILTIN[expr])
    if expr == "true":
        return Type("TRUE")
    if expr.startswith("%"):
        return Type("OBJECT", name=expr[1:], bare=True)
    last = expr.split(".")[-1]
    if last[0].islower():
        return Type("OBJECT", name=expr, bare=True, by_ctor=True)
    return Type("OBJECT", name=expr, bare=False)


class Ctor:
    pass


def parse_combinator(stmt, is_function, crc_line):
    if " = " not in stmt:
        raise SchemaError("no result type: " + stmt[:80])
    left, result = stmt.rsplit(" = ", 1)
    result = result.strip()
    parts = split_args(left.strip())
    head = parts[0]
    m = re.match(r"^([A-Za-z0-9_.]+)(?:#([0-9a-fA-F]{1,8}))?$", head)
    if not m:
        raise SchemaError("bad combinator name: " + head)
    c = Ctor()
    c.name = m.group(1)
    c.explicit_id = int(m.group(2), 16) if m.group(2) else None
    c.is_function = is_function
    generics = set()
    c.fields = []
    for p in parts[1:]:
        if p.startswith("{"):
            gm = re.match(r"^\{([A-Za-z0-9_]+):Type\}$", p)
            if not gm:
                raise SchemaError("bad generic: " + p)
            generics.add(gm.group(1))
            continue
        if p == "[" or p == "]" or p.startswith("["):
            raise SchemaError("array syntax is not supported: " + stmt[:60])
        fm = re.match(r"^([A-Za-z0-9_]+):(.+)$", p)
        if not fm:
            raise SchemaError("bad field %r in %s" % (p, c.name))
        fname, ftype = fm.group(1), fm.group(2)
        flags_field, flag_bit = None, None
        om = re.match(r"^([A-Za-z0-9_]+)\.(\d+)\?(.+)$", ftype)
        if om:
            flags_field, flag_bit, ftype = om.group(1), int(om.group(2)), om.group(3)
            if flag_bit > 31:
                raise SchemaError("flag bit out of range in " + c.name)
        c.fields.append((fname, parse_type(ftype, generics), flags_field, flag_bit, ftype))
    c.result_text = result
    c.result = parse_type(result, generics)
    if c.result.kind == "OBJECT":
        c.result.bare = False
    c.crc_skip = None
    if crc_line and crc_line.startswith("skip:"):
        c.crc_skip = crc_line[5:]
        crc_line = None
    c.crc_text = normalize_crc(crc_line) if crc_line else crc_text(c, parts, result)
    return c


def crc_text(c, parts, result):
    args = list(parts[1:])
    text = c.name + (" " + " ".join(args) if args else "") + " = " + result
    return normalize_crc(text)


def normalize_crc(text):
    text = text.replace(":bytes ", ":string ").replace("?bytes ", "?string ")
    text = text.replace("<", " ").replace(">", "").replace("{", "").replace("}", "")
    text = re.sub(r" \w+:\w+\.\d+\?true", "", text)
    # crc names must match telegram's bare-constructor spelling
    text = re.sub(r"%([A-Za-z0-9_.]+)", lambda m: m.group(1)[0].lower() + m.group(1)[1:], text)
    return text


def crc32(text):
    return binascii.crc32(text.encode("ascii")) & 0xFFFFFFFF


class Schema:
    def __init__(self):
        self.ctors = []
        self.layer = None

    def add_file(self, path):
        with open(path, "r", encoding="ascii") as f:
            text = f.read()
        stmts, layer = parse_statements(text)
        if layer is not None:
            self.layer = layer
        for stmt, is_function, crc_line in stmts:
            m = re.match(r"^([A-Za-z0-9_.]+)", stmt)
            if m and m.group(1) == "vector":
                continue
            c = parse_combinator(stmt, is_function, crc_line)
            computed = crc32(c.crc_text)
            if c.crc_skip is not None:
                if c.explicit_id is None:
                    raise SchemaError("crc-skip needs an explicit id: " + c.name)
                sys.stderr.write("tlgen: id of %s is not verified (%s)\n" % (c.name, c.crc_skip))
                computed = c.explicit_id
            if c.explicit_id is None:
                c.id = computed
            else:
                if c.explicit_id != computed:
                    raise SchemaError("%s: id %08x does not match crc32 %08x of '%s'" %
                                      (c.name, c.explicit_id, computed, c.crc_text))
                c.id = c.explicit_id
            c.source = os.path.basename(path)
            self.ctors.append(c)

    def finish(self):
        by_id, by_name = {}, {}
        unique = []
        for c in self.ctors:
            same = by_id.get(c.id)
            if same is not None:
                if same.crc_text == c.crc_text and same.is_function == c.is_function:
                    continue
                raise SchemaError("id clash between %s and %s" % (same.name, c.name))
            if c.name in by_name:
                raise SchemaError("name clash: " + c.name)
            by_id[c.id] = c
            by_name[c.name] = c
            unique.append(c)
        self.ctors = sorted(unique, key=lambda c: c.id)
        self.resolve_bare_references(by_name)
        self.build_tables()

    def resolve_bare_references(self, by_name):
        def walk(t):
            if t.by_ctor:
                target = by_name.get(t.name)
                if target is None or target.result.kind != "OBJECT":
                    raise SchemaError("bare reference to unknown constructor " + t.name)
                t.name = target.result.name
                t.by_ctor = False
            if t.elem:
                walk(t.elem)
        for c in self.ctors:
            for f in c.fields:
                walk(f[1])
            walk(c.result)

    def build_tables(self):
        type_names = {"Object"}
        for c in self.ctors:
            if c.result.kind == "OBJECT":
                type_names.add(c.result.name)

        def collect(t):
            if t.kind == "OBJECT" and not t.name == "Object":
                type_names.add(t.name)
            if t.elem:
                collect(t.elem)
        for c in self.ctors:
            for f in c.fields:
                collect(f[1])
            collect(c.result)
        self.type_names = sorted(type_names)
        self.type_name_id = {n: i for i, n in enumerate(self.type_names)}

        # a type no constructor returns can never be decoded, this catches typos in a schema
        produced = set()
        for c in self.ctors:
            if c.result.kind == "OBJECT":
                produced.add(c.result.name)
        for n in self.type_names:
            if n != "Object" and n not in produced:
                raise SchemaError("type %s is referenced but no constructor returns it" % n)

        self.types = []
        self.type_index = {}
        self.ref(Type("OBJECT", name="Object", bare=False))  # the runtime hardcodes reference 0 as the any object reference
        for c in self.ctors:
            c.result_ref = self.ref(c.result)
            c.field_refs = []
            names = [f[0] for f in c.fields]
            if len(set(names)) != len(names):
                raise SchemaError("duplicate field names in " + c.name)
            for idx, f in enumerate(c.fields):
                c.field_refs.append(self.ref(f[1]))
                if f[2] is not None:
                    if f[2] not in names:
                        raise SchemaError("%s: flags field %s is missing" % (c.name, f[2]))
                    fi = names.index(f[2])
                    if fi >= idx or c.fields[fi][1].kind != "FLAGS":
                        raise SchemaError("%s: field %s depends on a bad flags field" % (c.name, f[0]))
            if len(c.fields) > 255:
                raise SchemaError("too many fields in " + c.name)
        # a bare value carries no id, so the type must have exactly one constructor to pick
        counts = {}
        for c in self.ctors:
            if c.result.kind == "OBJECT" and not c.is_function:
                counts.setdefault(c.result.name, []).append(c)
        self.bare_ctor = []
        for n in self.type_names:
            lst = counts.get(n, [])
            self.bare_ctor.append(lst[0] if len(lst) == 1 else None)
        if len(self.types) > 65535:
            raise SchemaError("too many type references")

        def check_bare(t):
            if t.kind == "OBJECT" and t.bare and self.bare_ctor[self.type_name_id[t.name]] is None:
                raise SchemaError("bare type %s has no unique constructor" % t.name)
            if t.elem:
                check_bare(t.elem)
        for c in self.ctors:
            for f in c.fields:
                check_bare(f[1])

    def ref(self, t):
        key = t.key()
        if key in self.type_index:
            return self.type_index[key]
        elem_ref = self.ref(t.elem) if t.elem else 0
        idx = len(self.types)
        self.types.append((t, elem_ref))
        self.type_index[key] = idx
        return idx


def c_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def c_ident(name):
    return name.replace(".", "_")


def emit(schema, outdir):
    os.makedirs(outdir, exist_ok=True)
    first_field = []
    total = 0
    for c in schema.ctors:
        first_field.append(total)
        total += len(c.fields)

    lines = ["/* regenerate from the pinned schemas so constructor metadata stays consistent */", '#include "exteria_tl_schema.h"', ""]
    lines.append("const uint32_t exteria_tl_layer = %d;" % schema.layer)
    lines.append("")
    lines.append("const char *const exteria_tl_type_names[] = {")
    for n in schema.type_names:
        lines.append("    %s," % c_str(n))
    lines.append("};")
    lines.append("const uint32_t exteria_tl_type_name_count = %d;" % len(schema.type_names))
    lines.append("")
    lines.append("const exteria_tl_type exteria_tl_types[] = {")
    for t, elem_ref in schema.types:
        arg = schema.type_name_id[t.name] if t.kind == "OBJECT" else elem_ref
        lines.append("    { EXTERIA_TL_K_%s, %d, %d }," % (t.kind, 1 if t.bare else 0, arg))
    lines.append("};")
    lines.append("const uint32_t exteria_tl_type_count = %d;" % len(schema.types))
    lines.append("")
    lines.append("const int32_t exteria_tl_bare_ctor[] = {")
    index_of = {id(c): i for i, c in enumerate(schema.ctors)}
    for n, c in zip(schema.type_names, schema.bare_ctor):
        lines.append("    %d," % (index_of[id(c)] if c is not None else -1))
    lines.append("};")
    lines.append("")
    lines.append("const exteria_tl_field exteria_tl_fields[] = {")
    for c in schema.ctors:
        names = [f[0] for f in c.fields]
        for f, ref in zip(c.fields, c.field_refs):
            ff = names.index(f[2]) if f[2] is not None else 255
            fb = f[3] if f[3] is not None else 0
            lines.append("    { %s, %d, %d, %d }," % (c_str(f[0]), ref, ff, fb))
    if total == 0:
        lines.append("    { 0, 0, 0, 0 },")
    lines.append("};")
    lines.append("const uint32_t exteria_tl_field_count = %d;" % total)
    lines.append("")
    lines.append("const exteria_tl_ctor exteria_tl_ctors[] = {")
    for c, ff in zip(schema.ctors, first_field):
        tname = schema.type_name_id[c.result.name] if c.result.kind == "OBJECT" else 0
        lines.append("    { 0x%08xu, %d, %d, %du, %d, %d, %s }," %
                     (c.id, c.result_ref, tname, ff, len(c.fields), 1 if c.is_function else 0, c_str(c.name)))
    lines.append("};")
    lines.append("const uint32_t exteria_tl_ctor_count = %d;" % len(schema.ctors))
    lines.append("")
    by_name = sorted(range(len(schema.ctors)), key=lambda i: schema.ctors[i].name)
    lines.append("const uint32_t exteria_tl_ctors_by_name[] = {")
    for i in range(0, len(by_name), 12):
        lines.append("    " + ", ".join(str(x) for x in by_name[i:i + 12]) + ",")
    lines.append("};")
    lines.append("")
    with open(os.path.join(outdir, "exteria_tl_schema_data.c"), "w", encoding="ascii", newline="\n") as f:
        f.write("\n".join(lines))

    ids = ["/* regenerate from the pinned schemas so constructor metadata stays consistent */", "#ifndef EXTERIA_TL_IDS_H", "#define EXTERIA_TL_IDS_H", ""]
    ids.append("#define EXTERIA_TL_LAYER %d" % schema.layer)
    ids.append("")
    for c in sorted(schema.ctors, key=lambda c: c.name):
        ids.append("#define EXTERIA_TL_ID_%s 0x%08xu" % (c_ident(c.name), c.id))
    ids += ["", "#endif", ""]
    with open(os.path.join(outdir, "exteria_tl_ids.h"), "w", encoding="ascii", newline="\n") as f:
        f.write("\n".join(ids))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("files", nargs="+")
    args = ap.parse_args()
    schema = Schema()
    try:
        for p in args.files:
            schema.add_file(p)
        if schema.layer is None:
            raise SchemaError("no '// LAYER n' line in the schemas")
        schema.finish()
    except SchemaError as e:
        sys.stderr.write("tlgen: %s\n" % e)
        return 1
    emit(schema, args.out)
    print("tlgen: layer %d, %d constructors, %d fields, %d types" %
          (schema.layer, len(schema.ctors), sum(len(c.fields) for c in schema.ctors), len(schema.types)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
