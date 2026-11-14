"""android.text.method: what a TextView does with a touch on its text"""


class MovementMethod:
    """a program implements onTouchEvent(widget, text, event) and returns True when it took the touch"""


class LinkMovementMethod(MovementMethod):
    """a tap on a ClickableSpan (a URLSpan, or a subclass of a program) calls its onClick(widget)"""

    _instance = None

    @staticmethod
    def getInstance():
        if LinkMovementMethod._instance is None:
            LinkMovementMethod._instance = LinkMovementMethod()
        return LinkMovementMethod._instance

    def onTouchEvent(self, widget, text, event):
        from android.text import ClickableSpan
        from android.view import MotionEvent
        if event.getAction() != MotionEvent.ACTION_UP or not hasattr(text, "getSpans"):
            return False
        offset = widget.getOffsetForPosition(event.getX(), event.getY())
        if offset < 0:
            return False
        spans = text.getSpans(offset, offset + 1, ClickableSpan)
        # a character is hit when its span covers [offset, offset + 1), a span that ends at the offset is not under the finger
        hit = [s for s in spans if text.getSpanStart(s) <= offset < text.getSpanEnd(s)]
        if not hit:
            return False
        hit[-1].onClick(widget)
        return True


class ArrowKeyMovementMethod(MovementMethod):
    """the field of the app moves its own cursor with the finger and the keyboard, so there is nothing for this method to add"""

    _instance = None

    @staticmethod
    def getInstance():
        if ArrowKeyMovementMethod._instance is None:
            ArrowKeyMovementMethod._instance = ArrowKeyMovementMethod()
        return ArrowKeyMovementMethod._instance

    def onTouchEvent(self, widget, text, event):
        return False
