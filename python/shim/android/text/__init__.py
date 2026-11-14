"""android.text"""

from android.graphics import Paint


class InputType:
    TYPE_CLASS_TEXT = 1
    TYPE_CLASS_NUMBER = 2
    TYPE_CLASS_PHONE = 3
    TYPE_NUMBER_FLAG_DECIMAL = 8192
    TYPE_NUMBER_FLAG_SIGNED = 4096
    TYPE_TEXT_FLAG_MULTI_LINE = 131072
    TYPE_TEXT_VARIATION_PASSWORD = 128
    TYPE_TEXT_VARIATION_URI = 16


class TextUtils:
    class TruncateAt:
        START = "START"
        MIDDLE = "MIDDLE"
        END = "END"
        MARQUEE = "MARQUEE"

    @staticmethod
    def isEmpty(text):
        return text is None or len(text) == 0


class TextPaint(Paint):
    """a Paint that also carries the density and the colors a text style asks for"""

    def __init__(self, flags=0):
        Paint.__init__(self, flags)
        self.density = 1.0
        self.linkColor = 0
        self.bgColor = 0
        self.baselineShift = 0
        self.drawableState = None


class TextWatcher:
    """a program implements beforeTextChanged, onTextChanged and afterTextChanged"""


class InputFilter:
    """a program implements filter(source, start, end, dest, dstart, dend) and returns the replacement or null"""


class Spanned:
    SPAN_EXCLUSIVE_EXCLUSIVE = 33
    SPAN_EXCLUSIVE_INCLUSIVE = 34
    SPAN_INCLUSIVE_EXCLUSIVE = 17
    SPAN_INCLUSIVE_INCLUSIVE = 18
    SPAN_PARAGRAPH = 51
    SPAN_MARK_MARK = 17


class Spannable(Spanned):
    class Factory:
        pass


class SpannableStringBuilder(Spannable):
    """text with spans. a span covers [start, end); an edit moves the spans that lie after it, grows a span that the edit lands
    inside, and drops a span whose text is deleted whole, the way the android class does for exclusive ends"""

    def __init__(self, text="", start=None, end=None):
        self._text = ""
        if not isinstance(text, SpannableStringBuilder):
            text = "" if text is None else str(text)
            self._text = text[start:end] if start is not None else text
        self._spans = []
        if isinstance(text, SpannableStringBuilder):
            self._text = text._text[start:end] if start is not None else text._text
            low = start or 0
            for span, s, e, flags in text._spans:
                if end is None or s < end and e > low:
                    self._spans.append((span, max(s, low) - low, min(e, len(text._text) if end is None else end) - low, flags))

    def __len__(self):
        return len(self._text)

    def length(self):
        return len(self._text)

    def charAt(self, index):
        if not 0 <= index < len(self._text):
            raise IndexError("charAt: %d out of range of length %d" % (index, len(self._text)))
        return self._text[index]

    def toString(self):
        return self._text

    __str__ = toString

    def subSequence(self, start, end):
        result = SpannableStringBuilder(self._text[start:end])
        for span, s, e, flags in self._spans:
            if s < end and e > start:
                result._spans.append((span, max(s, start) - start, min(e, end) - start, flags))
        return result

    def setSpan(self, span, start, end, flags):
        if start < 0 or end > len(self._text) or start > end:
            raise IndexError("setSpan (%d ... %d) ends beyond length %d" % (start, end, len(self._text)))
        self._spans = [entry for entry in self._spans if entry[0] is not span]
        self._spans.append((span, start, end, flags))

    def removeSpan(self, span):
        self._spans = [entry for entry in self._spans if entry[0] is not span]

    def getSpanStart(self, span):
        for entry in self._spans:
            if entry[0] is span:
                return entry[1]
        return -1

    def getSpanEnd(self, span):
        for entry in self._spans:
            if entry[0] is span:
                return entry[2]
        return -1

    def getSpanFlags(self, span):
        for entry in self._spans:
            if entry[0] is span:
                return entry[3]
        return 0

    def getSpans(self, start, end, kind):
        found = []
        for span, s, e, _ in self._spans:
            if kind is not None and not _is_kind(span, kind):
                continue
            if s < end and e > start or (s == e and start <= s <= end):
                found.append(span)
        return found

    def nextSpanTransition(self, start, limit, kind):
        points = [p for _, s, e, _ in self._spans for p in (s, e) if start < p < limit]
        return min(points) if points else limit

    def _shift(self, at, removed, added):
        out = []
        for span, s, e, flags in self._spans:
            if at + removed <= s:
                s += added - removed
            elif at < s:
                s = at + added
            if at + removed <= e:
                e += added - removed
            elif at < e:
                e = at
            if e < s or (e == s and removed and s == at and flags == Spanned.SPAN_EXCLUSIVE_EXCLUSIVE):
                continue
            out.append((span, s, e, flags))
        self._spans = out

    def replace(self, start, end, text, text_start=None, text_end=None):
        text = str(text)
        if text_start is not None:
            text = text[text_start:text_end]
        if start < 0 or end > len(self._text) or start > end:
            raise IndexError("replace (%d ... %d) ends beyond length %d" % (start, end, len(self._text)))
        self._shift(start, end - start, len(text))
        self._text = self._text[:start] + text + self._text[end:]
        return self

    def append(self, text, what=None, flags=0):
        before = len(self._text)
        if isinstance(text, SpannableStringBuilder):
            offset = before
            self._text += text._text
            for span, s, e, f in text._spans:
                self._spans.append((span, s + offset, e + offset, f))
            return self
        self._text += chr(text) if isinstance(text, int) and not isinstance(text, bool) else str(text)
        if what is not None:
            self.setSpan(what, before, len(self._text), flags)
        return self

    def insert(self, where, text, start=None, end=None):
        return self.replace(where, where, text, start, end)

    def delete(self, start, end):
        return self.replace(start, end, "")

    def clear(self):
        self._text = ""
        self._spans = []

    def clearSpans(self):
        self._spans = []

    def setLength(self, length):
        self._text = self._text[:length].ljust(length, "\0")
        self._spans = [(s, a, min(b, length), f) for s, a, b, f in self._spans if a < length]

    def equals(self, other):
        return isinstance(other, SpannableStringBuilder) and other._text == self._text

    def hashCode(self):
        return hash(self._text) & 0x7FFFFFFF


class SpannableString(SpannableStringBuilder):
    """a SpannableStringBuilder whose text cannot change"""

    @staticmethod
    def valueOf(text):
        return text if isinstance(text, SpannableString) else SpannableString(text)

    def replace(self, *args):
        from java.lang import UnsupportedOperationException
        raise UnsupportedOperationException("a SpannableString has fixed text")

    append = insert = delete = clear = replace


def _is_kind(span, kind):
    return isinstance(span, kind) if isinstance(kind, type) else True


class CharacterStyle:
    """base of the spans that style characters; a plugin class may extend it and override updateDrawState"""

    def updateDrawState(self, paint):
        return None


class ClickableSpan(CharacterStyle):
    def onClick(self, widget):
        return None


class ForegroundColorSpan(CharacterStyle):
    def __init__(self, color):
        self._color = int(color) & 0xFFFFFFFF

    def getForegroundColor(self):
        return self._color


class BackgroundColorSpan(CharacterStyle):
    def __init__(self, color):
        self._color = int(color) & 0xFFFFFFFF

    def getBackgroundColor(self):
        return self._color


class StyleSpan(CharacterStyle):
    def __init__(self, style):
        self._style = style

    def getStyle(self):
        return self._style


class UnderlineSpan(CharacterStyle):
    pass


class StrikethroughSpan(CharacterStyle):
    pass


class AbsoluteSizeSpan(CharacterStyle):
    def __init__(self, size, dip=False):
        self._size = size
        self._dip = dip

    def getSize(self):
        return self._size


class ReplacementSpan(CharacterStyle):
    """a program implements getSize(paint, text, start, end, fm) and draw(canvas, ...)"""


class URLSpan(ClickableSpan):
    def __init__(self, url):
        self._url = str(url)

    def getURL(self):
        return self._url

    def onClick(self, widget):
        """opens the address as Browser.openUrl does: the app routes it, and a scheme it does not open is an IllegalArgumentException"""
        from org.telegram.messenger.browser import Browser
        Browser.openUrl(widget.getContext() if hasattr(widget, "getContext") else None, self._url)


class Annotation(CharacterStyle):
    def __init__(self, key, value):
        self._k, self._v = key, value

    def getKey(self):
        return self._k

    def getValue(self):
        return self._v


class ParagraphStyle:
    """the marker of the spans that style a paragraph"""


class MetricAffectingSpan(CharacterStyle):
    pass


class UpdateAppearance:
    pass


class UpdateLayout(UpdateAppearance):
    pass


class WrapTogetherSpan(ParagraphStyle):
    pass


class LeadingMarginSpan(ParagraphStyle):
    """a program implements getLeadingMargin(first), drawLeadingMargin(...)"""

    class Standard(Object if False else object):
        def __init__(self, first, rest=None):
            self._first, self._rest = first, first if rest is None else rest

        def getLeadingMargin(self, first):
            return self._first if first else self._rest


class AlignmentSpan(ParagraphStyle):
    class Standard(object):
        def __init__(self, alignment):
            self._a = alignment

        def getAlignment(self):
            return self._a


class BulletSpan(ParagraphStyle):
    def __init__(self, gap=2, color=0, radius=4):
        self._gap, self._color, self._radius = gap, color, radius

    def getLeadingMargin(self, first):
        return 2 * self._radius + self._gap


class QuoteSpan(ParagraphStyle):
    def __init__(self, color=0xFF0000FF, stripe=2, gap=2):
        self._color, self._stripe, self._gap = color, stripe, gap

    def getColor(self):
        return self._color

    def getLeadingMargin(self, first):
        return self._stripe + self._gap


class LineBackgroundSpan(ParagraphStyle):
    """a program implements drawBackground(...)"""

    class Standard(object):
        def __init__(self, color):
            self._c = color


class LineHeightSpan(ParagraphStyle):
    """a program implements chooseHeight(...)"""

    class Standard(object):
        def __init__(self, height):
            self._h = height

        def getHeight(self):
            return self._h


class TabStopSpan(ParagraphStyle):
    class Standard(object):
        def __init__(self, where):
            self._w = where


class RelativeSizeSpan(MetricAffectingSpan):
    def __init__(self, proportion):
        self._p = float(proportion)

    def getSizeChange(self):
        return self._p


class ScaleXSpan(MetricAffectingSpan):
    def __init__(self, proportion):
        self._p = float(proportion)

    def getScaleX(self):
        return self._p


class SubscriptSpan(MetricAffectingSpan):
    pass


class SuperscriptSpan(MetricAffectingSpan):
    pass


class TypefaceSpan(MetricAffectingSpan):
    def __init__(self, family):
        self._f = family if isinstance(family, str) else None
        self._t = None if isinstance(family, str) else family

    def getFamily(self):
        return self._f

    def getTypeface(self):
        return self._t


class TextAppearanceSpan(MetricAffectingSpan):
    def __init__(self, family=None, style=0, size=-1, color=None, link=None):
        self._family, self._style, self._size = family, style, size


class LocaleSpan(MetricAffectingSpan):
    def __init__(self, locale):
        self._l = locale

    def getLocale(self):
        return self._l


class MaskFilterSpan(CharacterStyle):
    def __init__(self, mask):
        self._m = mask

    def getMaskFilter(self):
        return self._m


class DynamicDrawableSpan(ReplacementSpan):
    ALIGN_BOTTOM = 0
    ALIGN_BASELINE = 1
    ALIGN_CENTER = 2

    def __init__(self, vertical_alignment=0):
        self._align = vertical_alignment

    def getVerticalAlignment(self):
        return self._align

    def getDrawable(self):
        return None


class ImageSpan(DynamicDrawableSpan):
    def __init__(self, drawable, vertical_alignment=0):
        DynamicDrawableSpan.__init__(self, vertical_alignment if isinstance(vertical_alignment, int) else 0)
        self._drawable = drawable

    def getDrawable(self):
        return self._drawable


class IconMarginSpan(ParagraphStyle):
    def __init__(self, bitmap, pad=0):
        self._b, self._pad = bitmap, pad


class DrawableMarginSpan(ParagraphStyle):
    def __init__(self, drawable, pad=0):
        self._d, self._pad = drawable, pad


class SuggestionSpan(CharacterStyle):
    pass


class SpellCheckSpan(CharacterStyle):
    pass


class EasyEditSpan(object):
    pass


class SuggestionRangeSpan(CharacterStyle):
    pass


class TtsSpan(object):
    pass


class SpannedString(SpannableStringBuilder):
    """text and spans that do not change"""

    def replace(self, *args):
        from java.lang import UnsupportedOperationException
        raise UnsupportedOperationException("a SpannedString has fixed text")

    append = insert = delete = clear = setSpan = removeSpan = replace


class Editable(Spannable):
    """what an EditText answers for getText(): text that can change"""

    class Factory(object):
        pass

    _jinterface = True


class Layout(object):
    class Alignment(object):
        ALIGN_NORMAL = "ALIGN_NORMAL"
        ALIGN_OPPOSITE = "ALIGN_OPPOSITE"
        ALIGN_CENTER = "ALIGN_CENTER"
    DIR_LEFT_TO_RIGHT = 1
    DIR_RIGHT_TO_LEFT = -1


class StaticLayout(Layout):
    """lines broken to a width at spaces, measured with the font of the app: getLineCount, getLineStart, getLineEnd, getLineWidth and getHeight"""

    def __init__(self, text, paint, width, alignment=None, spacing_mult=1.0, spacing_add=0.0, include_pad=True, *_rest):
        from android import _ui
        self._text = str(text)
        self._paint = paint
        self._width = int(width)
        self._lines = []
        line_start = 0
        pieces = []
        for paragraph in self._text.split("\n"):
            pieces.append(paragraph)
        offset = 0
        for paragraph in pieces:
            start = offset
            current = start
            words = []
            index = 0
            for token in __import__("re").finditer(r"\S+\s*|\s+", paragraph):
                words.append((start + token.start(), start + token.end()))
            if not words:
                self._lines.append((start, start))
            line_begin, line_end = None, None
            for begin, end in words:
                trial_begin = begin if line_begin is None else line_begin
                if line_begin is not None and paint.measureText(self._text[trial_begin:end].rstrip()) > self._width:
                    self._lines.append((line_begin, line_end))
                    line_begin, line_end = begin, end
                else:
                    line_begin, line_end = trial_begin, end
            if line_begin is not None:
                self._lines.append((line_begin, line_end))
            offset += len(paragraph) + 1
        metrics = paint.getFontMetrics()
        self._line_height = (metrics.descent - metrics.ascent) * spacing_mult + spacing_add
        self._ascent = metrics.ascent

    def getLineCount(self):
        return len(self._lines)

    def getLineStart(self, line):
        return self._lines[line][0]

    def getLineEnd(self, line):
        return self._lines[line][1]

    def getLineWidth(self, line):
        begin, end = self._lines[line]
        return self._paint.measureText(self._text[begin:end].rstrip())

    def getWidth(self):
        return self._width

    def getHeight(self):
        return int(round(self._line_height * len(self._lines)))

    def getLineTop(self, line):
        return int(round(self._line_height * line))

    def getLineBottom(self, line):
        return int(round(self._line_height * (line + 1)))

    def getLineBaseline(self, line):
        return int(round(self._line_height * line - self._ascent))

    def getLineForOffset(self, offset):
        for index, (begin, end) in enumerate(self._lines):
            if begin <= offset < end:
                return index
        return max(0, len(self._lines) - 1)

    def getText(self):
        return self._text

    def getPaint(self):
        return self._paint

    @staticmethod
    def obtain(text, start, end, paint, width):
        return StaticLayout(str(text)[start:end], paint, width)

    class Builder(object):
        def __init__(self, text, start, end, paint, width):
            self._args = (str(text)[start:end], paint, width)

        @staticmethod
        def obtain(text, start, end, paint, width):
            return StaticLayout.Builder(text, start, end, paint, width)

        def __getattr__(self, name):
            def keep(*_a):
                return self
            return keep

        def build(self):
            return StaticLayout(*self._args)


class Html:
    """fromHtml for the tags a plugin writes into a message or a dialog: b, strong, i, em, u, s, strike, del, a, br, p, div, h1 to h6, li,
    code, tt, pre and the entities. any other tag only keeps its text. the text is not drawn with the spans on ios (see TextView), they are
    there for getSpans and for a tap on a link"""

    FROM_HTML_MODE_LEGACY = 0
    FROM_HTML_MODE_COMPACT = 63
    FROM_HTML_SEPARATOR_LINE_BREAK_PARAGRAPH = 1
    FROM_HTML_SEPARATOR_LINE_BREAK_LIST_ITEM = 2
    TO_HTML_PARAGRAPH_LINES_CONSECUTIVE = 0
    MAX_DEPTH = 256

    @staticmethod
    def fromHtml(source, flags=0, *_image_and_tag_handlers):
        from html.parser import HTMLParser
        from android.graphics import Typeface

        out = SpannableStringBuilder()
        open_spans = []
        sizes = {"h1": 1.5, "h2": 1.4, "h3": 1.3, "h4": 1.2, "h5": 1.1, "h6": 1.0}

        def block_break(count):
            """Android starts a block on a new line and ends it with a blank line: a break is added only up to the wanted run of newlines"""
            text = str(out)
            have = len(text) - len(text.rstrip("\n"))
            if text:
                out.append("\n" * max(0, count - have))

        def make(tag, attrs):
            if tag in ("b", "strong"):
                return [StyleSpan(Typeface.BOLD)]
            if tag in ("i", "em", "cite", "dfn"):
                return [StyleSpan(2)]
            if tag == "u":
                return [UnderlineSpan()]
            if tag in ("s", "strike", "del"):
                return [StrikethroughSpan()]
            if tag in ("code", "tt", "pre"):
                return [TypefaceSpan("monospace")]
            if tag == "a" and attrs.get("href") is not None:
                return [URLSpan(attrs["href"])]
            if tag in sizes:
                return [RelativeSizeSpan(sizes[tag]), StyleSpan(Typeface.BOLD)]
            return []

        class Reader(HTMLParser):
            def __init__(self):
                super().__init__(convert_charrefs=True)

            def handle_starttag(self, tag, attrs):
                if tag == "br":
                    out.append("\n")
                    return
                if len(open_spans) >= Html.MAX_DEPTH:
                    raise ValueError("html nested deeper than %d tags" % Html.MAX_DEPTH)
                if tag in ("p", "div") or tag in sizes:
                    block_break(1 if tag == "div" else 2)
                elif tag == "li":
                    block_break(1)
                    out.append("• ")
                open_spans.append((tag, len(out), make(tag, dict(attrs))))

            def handle_startendtag(self, tag, attrs):
                if tag == "br":
                    out.append("\n")

            def handle_endtag(self, tag):
                for index in range(len(open_spans) - 1, -1, -1):
                    if open_spans[index][0] == tag:
                        _tag, start, spans = open_spans.pop(index)
                        end = len(out)
                        if end > start:
                            for span in spans:
                                out.setSpan(span, start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                        if tag in ("p", "div") or tag in sizes:
                            block_break(1 if tag == "div" else 2)
                        return

            def handle_data(self, data):
                out.append(data)

        reader = Reader()
        reader.feed("" if source is None else str(source))
        reader.close()
        # a tag left open runs to the end of the text, as the tag soup of android closes it
        while open_spans:
            _tag, start, spans = open_spans.pop()
            if len(out) > start:
                for span in spans:
                    out.setSpan(span, start, len(out), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        return SpannedString(out)
