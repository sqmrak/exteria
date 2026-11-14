"""java.text.Bidi: the Unicode bidirectional algorithm (UAX #9, explicit embeddings and overrides, weak and neutral types, implicit levels, the
reset of trailing white space), runs, line Bidi objects and reorderVisually

the isolate controls (LRI, RLI, FSI, PDI) are treated as neutral characters, as the Bidi of the jdk did before it knew them, and
bracket pairs are not looked at"""

import unicodedata

from . import runtime
from .api import host_class, jmethod, jstatic
from .jlang import Object, jstr
from .jutil import check_nonnull

L, R, AL, EN, ES, ET, AN, CS, NSM, BN, B, S, WS, ON, LRE, LRO, RLE, RLO, PDF = range(19)
_TYPES = {"L": L, "R": R, "AL": AL, "EN": EN, "ES": ES, "ET": ET, "AN": AN, "CS": CS, "NSM": NSM, "BN": BN, "B": B, "S": S, "WS": WS,
          "ON": ON, "LRE": LRE, "LRO": LRO, "RLE": RLE, "RLO": RLO, "PDF": PDF, "LRI": ON, "RLI": ON, "FSI": ON, "PDI": ON}

MAX_DEPTH = 61


def classify(ch):
    return _TYPES.get(unicodedata.bidirectional(ch), L)


def _strong_direction(types, start, end):
    for i in range(start, end):
        t = types[i]
        if t == L:
            return 0
        if t in (R, AL):
            return 1
    return None


def resolve_levels(text, flags, embeddings=None):
    """(level of the first paragraph, levels) for a string; each paragraph ends with a paragraph separator and has its own level"""
    n = len(text)
    first_para, levels = None, [0] * n
    start = 0
    while start < n or first_para is None:
        end = start
        while end < n and classify(text[end]) != B:
            end += 1
        if end < n:
            end += 1
        para, part = _resolve_paragraph(text[start:end], flags, None if embeddings is None else embeddings[start:end], n == end - start)
        if first_para is None:
            first_para = para
        levels[start:end] = part
        if end >= n:
            break
        start = end
    return first_para, levels


def _resolve_paragraph(text, flags, embeddings, whole):
    n = len(text)
    types = [classify(c) for c in text]
    if flags == 0:
        para = 0
    elif flags == 1:
        para = 1
    else:
        found = _strong_direction(types, 0, n)
        para = found if found is not None else (1 if flags == -1 else 0)
    initial = list(types)
    levels = [para] * n
    # explicit levels (X1-X9)
    stack = [(para, None)]
    overflow = 0
    explicit = False
    for i in range(n):
        t = types[i]
        level, override = stack[-1]
        if embeddings is not None and embeddings[i] != 0:
            explicit = True
            e = embeddings[i]
            if e < 0:
                level = -e
                override = L if level % 2 == 0 else R
            else:
                level, override = e, None
            levels[i] = level
            if override is not None and t not in (B, S):
                types[i] = override
            continue
        if t in (LRE, LRO, RLE, RLO):
            explicit = True
            cur = stack[-1][0]
            new = (cur + 2) & ~1 if t in (LRE, LRO) else (cur + 1) | 1
            if new <= MAX_DEPTH and overflow == 0:
                stack.append((new, L if t == LRO else R if t == RLO else None))
            else:
                overflow += 1
            levels[i] = cur
            types[i] = BN
        elif t == PDF:
            explicit = True
            if overflow:
                overflow -= 1
            elif len(stack) > 1:
                stack.pop()
            levels[i] = stack[-1][0]
            types[i] = BN
        elif t == B:
            levels[i] = para
        else:
            levels[i] = level
            if override is not None and t != BN:
                types[i] = override
    if explicit and whole:
        # a text whose overridden types are all of the direction of the paragraph is not looked at further
        seen = {types[i] for i in range(n) if initial[i] not in (LRE, LRO, RLE, RLO, PDF, BN)}
        has_rtl = bool(seen & {R, AL, AN}) or any(
            initial[i] in (RLE, RLO) for i in range(n))
        has_ltr = bool(seen & {L, EN}) or any(initial[i] in (LRE, LRO) for i in range(n))
        has_ltr = has_ltr or para % 2 == 0
        has_rtl = has_rtl or para % 2 == 1
        if not has_rtl and para % 2 == 0:
            return para, [para] * n
        if not has_ltr and para % 2 == 1:
            return para, [para] * n
    i = 0
    while i < n:
        j = i
        while j < n and levels[j] == levels[i]:
            j += 1
        _resolve_run(types, initial, levels, i, j, para)
        i = j
    # the explicit controls take the level of the character that follows them
    for i in range(n - 1, -1, -1):
        if initial[i] in (LRE, LRO, RLE, RLO, PDF):
            levels[i] = levels[i + 1] if i + 1 < n else para
    # L1
    for i in range(n):
        if initial[i] in (B, S):
            levels[i] = para
            j = i - 1
            while j >= 0 and (initial[j] in (WS, BN, LRE, RLE, LRO, RLO, PDF)):
                levels[j] = para
                j -= 1
    j = n - 1
    while j >= 0 and initial[j] in (WS, BN, LRE, RLE, LRO, RLO, PDF):
        levels[j] = para
        j -= 1
    return para, levels


def _resolve_run(types, initial, levels, start, end, para):
    level = levels[start]
    # sos and eos
    prev_level = para
    k = start - 1
    while k >= 0 and initial[k] == BN:
        k -= 1
    if k >= 0:
        prev_level = levels[k]
    next_level = para
    k = end
    n = len(types)
    while k < n and initial[k] == BN:
        k += 1
    if k < n:
        next_level = levels[k]
    sos = R if max(level, prev_level) % 2 else L
    eos = R if max(level, next_level) % 2 else L
    idx = [i for i in range(start, end) if types[i] != BN]
    if not idx:
        return
    t = [types[i] for i in idx]
    m = len(t)
    # W1
    prev = sos
    for k in range(m):
        if t[k] == NSM:
            t[k] = prev
        else:
            prev = t[k]
    # W2
    last_strong = sos
    for k in range(m):
        if t[k] in (L, R, AL):
            last_strong = t[k]
        elif t[k] == EN and last_strong == AL:
            t[k] = AN
    # W3
    for k in range(m):
        if t[k] == AL:
            t[k] = R
    # W4
    for k in range(1, m - 1):
        if t[k] == ES and t[k - 1] == EN and t[k + 1] == EN:
            t[k] = EN
        elif t[k] == CS and t[k - 1] == t[k + 1] and t[k - 1] in (EN, AN):
            t[k] = t[k - 1]
    # W5
    k = 0
    while k < m:
        if t[k] == ET:
            j = k
            while j < m and t[j] == ET:
                j += 1
            if (k > 0 and t[k - 1] == EN) or (j < m and t[j] == EN):
                for q in range(k, j):
                    t[q] = EN
            k = j
        else:
            k += 1
    # W6
    for k in range(m):
        if t[k] in (ES, ET, CS):
            t[k] = ON
    # W7
    last_strong = sos
    for k in range(m):
        if t[k] in (L, R):
            last_strong = t[k]
        elif t[k] == EN and last_strong == L:
            t[k] = L
    # N1, N2
    k = 0
    while k < m:
        if t[k] in (B, S, WS, ON):
            j = k
            while j < m and t[j] in (B, S, WS, ON):
                j += 1

            def side(v):
                return R if v in (R, EN, AN) else L
            before = side(t[k - 1]) if k > 0 else sos
            after = side(t[j]) if j < m else eos
            direction = before if before == after else (R if level % 2 else L)
            for q in range(k, j):
                t[q] = direction
            k = j
        else:
            k += 1
    # I1, I2
    for k, i in enumerate(idx):
        v = t[k]
        if level % 2 == 0:
            if v == R:
                levels[i] = level + 1
            elif v in (AN, EN):
                levels[i] = level + 2
        else:
            if v in (L, EN, AN):
                levels[i] = level + 1
    # controls removed from the algorithm take the level of the neighbour before them
    for i in range(start, end):
        if types[i] == BN or initial[i] == BN:
            prev_i = i - 1
            levels[i] = levels[prev_i] if prev_i >= start else levels[i]


@host_class("java.text.Bidi")
class Bidi(Object):
    DIRECTION_LEFT_TO_RIGHT = 0
    DIRECTION_RIGHT_TO_LEFT = 1
    DIRECTION_DEFAULT_LEFT_TO_RIGHT = -2
    DIRECTION_DEFAULT_RIGHT_TO_LEFT = -1

    def __init__(self):
        self._text = ""
        self._flags = 0
        self._para = 0
        self._levels = []
        self._runs = []

    def _setup(self, text, flags, embeddings):
        self._text = text
        self._flags = flags
        self._para, self._levels = resolve_levels(text, flags, embeddings)
        self._runs = self._compute_runs()

    def _compute_runs(self):
        runs = []
        if not self._levels:
            return runs
        n = len(self._levels)
        i = 0
        while i < n:
            j = i
            while j < n and self._levels[j] == self._levels[i]:
                j += 1
            runs.append((i, j, self._levels[i]))
            i = j
        return runs

    @jmethod("<init>", "(Ljava/lang/String;I)V")
    def _init_string(self, text, flags):
        if text is None:
            runtime.throw_new("java.lang.IllegalArgumentException", None)
        self._setup(text, flags, None)

    @jmethod("<init>", "(Ljava/text/AttributedCharacterIterator;)V")
    def _init_iter(self, iterator):
        chars = []
        c0 = iterator.first()
        while c0 != "\uffff":
            chars.append(c0)
            c0 = iterator.next()
        self._setup("".join(chars), 0, None)

    @jmethod("<init>", "([CI[BIII)V")
    def _init_chars(self, chars, start, embeddings, emb_start, length, flags):
        if start < 0 or length < 0 or start + length > len(chars):
            runtime.throw_new("java.lang.IllegalArgumentException", "bad range: %d length: %d for text of length: %d" % (start, length, len(chars)))
        text = "".join(chr(c) if isinstance(c, int) else c for c in chars[start:start + length])
        emb = None
        if embeddings is not None:
            emb = [embeddings[emb_start + i] for i in range(length)]
        self._setup(text, flags, emb)

    @staticmethod
    def _line(parent, start, limit):
        b = Bidi()
        b._text = parent._text[start:limit]
        b._flags = parent._flags
        b._para = parent._para
        b._levels = list(parent._levels[start:limit])
        b._runs = b._compute_runs()
        return b

    @jmethod("createLineBidi", "(II)Ljava/text/Bidi;")
    def createLineBidi(self, start, limit):
        n = len(self._text)
        if not 0 <= start < limit:
            runtime.throw_new("java.lang.IllegalArgumentException", "Value %d is out of range %d to %d" % (start, 0, limit))
        if not 0 <= limit <= n:
            runtime.throw_new("java.lang.IllegalArgumentException", "Value %d is out of range %d to %d" % (limit, 0, n + 1))
        return Bidi._line(self, start, limit)

    def isMixed(self):
        return 1 if self._uniform() is None else 0

    def isLeftToRight(self):
        return 1 if self._uniform() == 0 else 0

    def isRightToLeft(self):
        return 1 if self._uniform() == 1 else 0

    def _uniform(self):
        """0 when everything is left to right, 1 when everything is right to left, else None"""
        if all(v == 0 for v in self._levels) and self._para == 0:
            return 0
        if all(v == 1 for v in self._levels) and self._para == 1:
            return 1
        return None

    def baseIsLeftToRight(self):
        return 1 if self._para % 2 == 0 else 0

    def getBaseLevel(self):
        return self._para

    def getLength(self):
        return len(self._text)

    def getLevelAt(self, offset):
        if offset < 0 or offset >= len(self._levels):
            return self._para
        return self._levels[offset]

    def getRunCount(self):
        return len(self._runs)

    def getRunLevel(self, run):
        return self._run(run)[2]

    def getRunStart(self, run):
        return self._run(run)[0]

    def getRunLimit(self, run):
        return self._run(run)[1]

    def _run(self, run):
        if not self._runs:
            return (0, 0, self._para)
        if run < 0 or run >= len(self._runs):
            runtime.throw_new("java.lang.ArrayIndexOutOfBoundsException", "Index %d out of bounds for length %d" % (run, len(self._runs)))
        return self._runs[run]

    @staticmethod
    def requiresBidi(text, start, limit):
        for i in range(start, limit):
            c = chr(text[i]) if isinstance(text[i], int) else text[i]
            t = classify(c)
            if t in (R, AL, AN, RLE, RLO, LRE, LRO, PDF):
                return 1
        return 0

    @staticmethod
    def reorderVisually(levels, level_start, objects, object_start, count):
        if not 0 <= level_start < len(levels):
            runtime.throw_new("java.lang.IllegalArgumentException", "Value levelStart %d is out of range 0 to %d" % (level_start, len(levels) - 1))
        if not 0 <= object_start < len(objects):
            runtime.throw_new("java.lang.IllegalArgumentException", "Value objectStart %d is out of range 0 to %d" % (object_start, len(objects) - 1))
        if count < 0 or level_start + count > len(levels) or object_start + count > len(objects):
            runtime.throw_new("java.lang.ArrayIndexOutOfBoundsException", "Index %d out of bounds for length %d" % (level_start + count, len(levels)))
        lv = [levels[level_start + i] for i in range(count)]
        order = list(range(count))
        if count:
            highest = max(lv)
            lowest_odd = min([v for v in lv if v % 2] or [highest + 1])
            level = highest
            while level >= lowest_odd:
                i = 0
                while i < count:
                    if lv[order[i]] >= level:
                        j = i
                        while j < count and lv[order[j]] >= level:
                            j += 1
                        order[i:j] = reversed(order[i:j])
                        i = j
                    else:
                        i += 1
                level -= 1
        items = [objects[object_start + i] for i in range(count)]
        for i in range(count):
            objects[object_start + i] = items[order[i]]

    def toString(self):
        u = self._uniform()
        direction = 2 if u is None else u
        return jstr("jdk.internal.icu.text.BidiBase[dir: %d baselevel: %d length: %d runs: [%s] text: [%s]]" % (
            direction, self._para, len(self._text), " ".join(str(v) for v in self._levels),
            " ".join("0x%x" % ord(c) for c in self._text)))
