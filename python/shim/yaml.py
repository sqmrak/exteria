"""the part of pyyaml that elyx_runtime calls: safe_load, for the metainfo, refmap, locale and data files of a plugin.

supported: block mappings and sequences, plain and quoted scalars, flow lists and maps on one line, `|` and `>` block
scalars, comments, ints, floats, bools, null and iso dates. anchors, aliases, tags, merge keys, multi line flow
collections, multi line plain scalars and several documents raise YAMLError, so a file that needs them fails loudly
instead of loading as something else"""

import datetime
import re

__all__ = ["safe_load", "YAMLError"]


class YAMLError(ValueError):
    pass


_INT = re.compile(r"^[-+]?(0|[1-9][0-9_]*)$")
_HEX = re.compile(r"^0x[0-9a-fA-F_]+$")
_FLOAT = re.compile(r"^[-+]?(\.[0-9]+|[0-9][0-9_]*(\.[0-9_]*)?)([eE][-+]?[0-9]+)?$")
_DATE = re.compile(r"^([0-9]{4})-([0-9]{2})-([0-9]{2})$")
_TRUE = ("true", "True", "TRUE")
_FALSE = ("false", "False", "FALSE")
_NULL = ("", "~", "null", "Null", "NULL")
_ESCAPES = {"0": "\0", "a": "\a", "b": "\b", "t": "\t", "n": "\n", "v": "\v", "f": "\f", "r": "\r", "e": "\x1b",
            " ": " ", '"': '"', "/": "/", "\\": "\\", "N": "\x85", "_": "\xa0", "L": " ", "P": " "}


def _plain(text):
    if text in _NULL:
        return None
    if text in _TRUE:
        return True
    if text in _FALSE:
        return False
    if _INT.match(text):
        return int(text.replace("_", ""))
    if _HEX.match(text):
        return int(text.replace("_", ""), 16)
    if _FLOAT.match(text) and any(c.isdigit() for c in text):
        return float(text.replace("_", ""))
    date = _DATE.match(text)
    if date:
        try:
            return datetime.date(*map(int, date.groups()))
        except ValueError:
            raise YAMLError("bad date: %s" % text)
    if text[0] in "&*!%@`":
        raise YAMLError("not supported: %s" % text)
    return text


def _double_quoted(text, at):
    """the text between the quotes of a double quoted scalar starting at text[at]; returns (value, end index)"""
    out = []
    i = at + 1
    while i < len(text):
        c = text[i]
        if c == '"':
            return "".join(out), i + 1
        if c != "\\":
            out.append(c)
            i += 1
            continue
        i += 1
        if i >= len(text):
            break
        e = text[i]
        width = {"x": 2, "u": 4, "U": 8}.get(e)
        if width:
            digits = text[i + 1:i + 1 + width]
            if len(digits) != width:
                raise YAMLError("short escape in a quoted string")
            try:
                out.append(chr(int(digits, 16)))
            except ValueError:
                raise YAMLError("bad escape in a quoted string")
            i += 1 + width
        elif e in _ESCAPES:
            out.append(_ESCAPES[e])
            i += 1
        else:
            raise YAMLError("unknown escape \\%s" % e)
    raise YAMLError("a quoted string is not closed")


def _single_quoted(text, at):
    out = []
    i = at + 1
    while i < len(text):
        if text[i] == "'":
            if text[i + 1:i + 2] == "'":
                out.append("'")
                i += 2
                continue
            return "".join(out), i + 1
        out.append(text[i])
        i += 1
    raise YAMLError("a quoted string is not closed")


def _strip_comment(text):
    """drops a trailing ` #...` outside quotes"""
    quote = None
    for i, c in enumerate(text):
        if quote:
            if c == "\\" and quote == '"':
                continue
            if c == quote:
                quote = None
        elif c in "\"'" and (i == 0 or text[i - 1] in " \t[{,:"):
            quote = c
        elif c == "#" and (i == 0 or text[i - 1] in " \t"):
            return text[:i].rstrip()
    return text.rstrip()


class _Flow:
    """a flow list or map confined to one line"""

    def __init__(self, text):
        self.text = text
        self.at = 0

    def _space(self):
        while self.at < len(self.text) and self.text[self.at] in " \t":
            self.at += 1

    def value(self, stops):
        self._space()
        if self.at >= len(self.text):
            raise YAMLError("a flow collection is not closed")
        c = self.text[self.at]
        if c == "[":
            self.at += 1
            items = []
            while True:
                self._space()
                if self.text[self.at:self.at + 1] == "]":
                    self.at += 1
                    return items
                items.append(self.value(",]"))
                self._space()
                if self.text[self.at:self.at + 1] == ",":
                    self.at += 1
                elif self.text[self.at:self.at + 1] != "]":
                    raise YAMLError("a flow list is not closed")
        if c == "{":
            self.at += 1
            mapping = {}
            while True:
                self._space()
                if self.text[self.at:self.at + 1] == "}":
                    self.at += 1
                    return mapping
                key = self.value(":,}")
                self._space()
                if self.text[self.at:self.at + 1] != ":":
                    raise YAMLError("a flow map key has no value")
                self.at += 1
                mapping[key] = self.value(",}")
                self._space()
                if self.text[self.at:self.at + 1] == ",":
                    self.at += 1
                elif self.text[self.at:self.at + 1] != "}":
                    raise YAMLError("a flow map is not closed")
        if c == '"':
            value, self.at = _double_quoted(self.text, self.at)
            return value
        if c == "'":
            value, self.at = _single_quoted(self.text, self.at)
            return value
        start = self.at
        while self.at < len(self.text) and self.text[self.at] not in stops:
            self.at += 1
        return _plain(self.text[start:self.at].strip())


def _scalar(text):
    """a one line value: quoted, flow collection or plain"""
    if text[:1] == '"':
        value, end = _double_quoted(text, 0)
        if text[end:].strip():
            raise YAMLError("text after a quoted string: %s" % text)
        return value
    if text[:1] == "'":
        value, end = _single_quoted(text, 0)
        if text[end:].strip():
            raise YAMLError("text after a quoted string: %s" % text)
        return value
    if text[:1] in "[{":
        flow = _Flow(text)
        value = flow.value("")
        if text[flow.at:].strip():
            raise YAMLError("text after a flow collection: %s" % text)
        return value
    return _plain(text)


def _split_key(text):
    """(key, rest) when the line is `key: rest`, else None"""
    if text[:1] in "\"'":
        reader = _double_quoted if text[0] == '"' else _single_quoted
        key, end = reader(text, 0)
        rest = text[end:].lstrip()
        if rest[:1] == ":" and (len(rest) == 1 or rest[1] in " \t"):
            return key, rest[1:].strip()
        return None
    match = re.match(r"^([^\s:#\[\]{},&*!|>%@`'\"][^:#]*?|[^\s:#\[\]{},&*!|>%@`'\"])\s*:(?:\s+(.*)|$)", text)
    if not match:
        return None
    return match.group(1), (match.group(2) or "").strip()


class _Line:
    __slots__ = ("indent", "text", "number", "raw")

    def __init__(self, indent, text, number, raw):
        self.indent = indent
        self.text = text
        self.number = number
        self.raw = raw


class _Parser:
    def __init__(self, source):
        self.lines = []
        for number, raw in enumerate(source.split("\n"), 1):
            raw = raw.rstrip("\r")
            if "\t" in raw[:len(raw) - len(raw.lstrip(" \t"))]:
                raise YAMLError("line %d: a tab in the indentation" % number)
            body = raw.strip()
            if not body or body.startswith("#"):
                self.lines.append(_Line(-1, "", number, raw))
                continue
            if body in ("---", "...") and not raw[:1].isspace():
                if body == "---" and not any(line.indent >= 0 for line in self.lines):
                    continue
                raise YAMLError("line %d: several documents are not supported" % number)
            self.lines.append(_Line(len(raw) - len(raw.lstrip(" ")), _strip_comment(body), number, raw))
        self.at = 0

    def _skip(self):
        while self.at < len(self.lines) and self.lines[self.at].indent < 0:
            self.at += 1

    def document(self):
        self._skip()
        if self.at >= len(self.lines):
            return None
        value = self.node(self.lines[self.at].indent)
        self._skip()
        if self.at < len(self.lines):
            raise YAMLError("line %d: unexpected indentation" % self.lines[self.at].number)
        return value

    def node(self, indent):
        line = self.lines[self.at]
        if line.text == "-" or line.text.startswith("- "):
            return self.sequence(indent)
        if _split_key(line.text):
            return self.mapping(indent)
        self.at += 1
        self._reject_continuation(line)
        return _scalar(line.text)

    def _reject_continuation(self, line):
        self._skip()
        if self.at < len(self.lines) and self.lines[self.at].indent > line.indent:
            raise YAMLError("line %d: a multi line plain scalar is not supported" % self.lines[self.at].number)

    def mapping(self, indent):
        result = {}
        while True:
            self._skip()
            if self.at >= len(self.lines) or self.lines[self.at].indent != indent:
                if self.at < len(self.lines) and self.lines[self.at].indent > indent:
                    raise YAMLError("line %d: unexpected indentation" % self.lines[self.at].number)
                return result
            line = self.lines[self.at]
            pair = _split_key(line.text)
            if pair is None:
                raise YAMLError("line %d: expected `key: value`" % line.number)
            key, rest = pair
            if key == "<<":
                raise YAMLError("line %d: merge keys are not supported" % line.number)
            if key in result:
                raise YAMLError("line %d: duplicate key %s" % (line.number, key))
            self.at += 1
            result[key] = self.value(line, rest)

    def sequence(self, indent):
        result = []
        while True:
            self._skip()
            if self.at >= len(self.lines) or self.lines[self.at].indent != indent:
                if self.at < len(self.lines) and self.lines[self.at].indent > indent:
                    raise YAMLError("line %d: unexpected indentation" % self.lines[self.at].number)
                return result
            line = self.lines[self.at]
            if not (line.text == "-" or line.text.startswith("- ")):
                return result
            rest = line.text[1:].lstrip()
            if not rest:
                self.at += 1
                self._skip()
                if self.at < len(self.lines) and self.lines[self.at].indent > indent:
                    result.append(self.node(self.lines[self.at].indent))
                else:
                    result.append(None)
                continue
            # `- key: value` opens a mapping whose keys sit at the column of the first key
            offset = len(line.raw) - len(line.raw.lstrip(" ")) + 1
            offset += len(line.raw[offset:]) - len(line.raw[offset:].lstrip(" "))
            if _split_key(rest):
                self.lines[self.at] = _Line(offset, rest, line.number, " " * offset + rest)
                result.append(self.mapping(offset))
            else:
                self.at += 1
                result.append(self.value(line, rest))

    def value(self, line, rest):
        if rest[:1] in ("|", ">"):
            return self.block_scalar(line, rest)
        if rest and rest[0] in "&*!":
            raise YAMLError("line %d: anchors, aliases and tags are not supported" % line.number)
        if rest:
            result = _scalar(rest)
            self._reject_continuation(line)
            return result
        self._skip()
        if self.at < len(self.lines):
            nxt = self.lines[self.at]
            if nxt.indent > line.indent:
                return self.node(nxt.indent)
            # a sequence may sit at the indent of its key
            if nxt.indent == line.indent and (nxt.text == "-" or nxt.text.startswith("- ")):
                return self.sequence(nxt.indent)
        return None

    def block_scalar(self, line, header):
        match = re.match(r"^([|>])([+-]?)([1-9]?)$", header) or re.match(r"^([|>])([1-9]?)([+-]?)$", header)
        if not match:
            raise YAMLError("line %d: bad block scalar header %s" % (line.number, header))
        style = match.group(1)
        flags = match.group(2) + match.group(3)
        chomp = "-" if "-" in flags else "+" if "+" in flags else ""
        explicit = next((int(c) for c in flags if c.isdigit()), 0)
        body = []
        base = line.indent + explicit if explicit else None
        while self.at < len(self.lines):
            nxt = self.lines[self.at]
            if nxt.indent >= 0:
                if base is None:
                    if nxt.indent <= line.indent:
                        break
                    base = nxt.indent
                elif nxt.indent < base:
                    break
            elif nxt.raw.strip() and not nxt.raw.lstrip().startswith("#"):
                break
            if nxt.indent < 0 and nxt.raw.lstrip().startswith("#") and (base is None or len(nxt.raw) - len(nxt.raw.lstrip()) < base):
                break
            body.append(nxt.raw[base:] if base is not None and len(nxt.raw) >= base else "")
            self.at += 1
        trailing = 0
        while body and not body[-1].strip():
            body.pop()
            trailing += 1
        if style == "|":
            text = "\n".join(body)
        else:
            # folded: a line break between two text lines is a space, a blank line is a break
            text = ""
            for i, one in enumerate(body):
                if i:
                    text += "\n" if not one.strip() or not body[i - 1].strip() else " "
                    if not one.strip() and body[i - 1].strip():
                        text = text[:-1]
                text += one
        if not body:
            return ""
        if chomp == "+":
            return text + "\n" * (1 + trailing)
        return text if chomp == "-" else text + "\n"


def safe_load(stream):
    if hasattr(stream, "read"):
        stream = stream.read()
    if isinstance(stream, bytes):
        stream = stream.decode("utf-8")
    if not isinstance(stream, str):
        raise YAMLError("safe_load takes text, bytes or a file")
    return _Parser(stream).document()
