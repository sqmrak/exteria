from android.view import ViewGroup
from android.graphics.drawable import GradientDrawable
from android.view import WRAP_CONTENT, Gravity, View
from android.widget import LinearLayout, TextView


class ChatMessageCell(ViewGroup):
    """the cell of a message in the android chat list. the app draws its own cells, so a view of this class is never shown;
    setMessageContent is the call the host makes for each message it is about to lay out, before it takes the text. a hook
    on it may change messageObject.messageText (and applyNewText), and the host shows the changed text"""

    def setMessageContent(self, message_object, grouped_messages=None, bottom_near=False, top_near=False):
        pass


class _CheckCell(LinearLayout):
    """a row with a round indicator and a text. the indicator is a filled disc when checked and a ring when not"""

    SIZE = 22
    ON = 0xFF2481CC
    OFF = 0xFF8E8E93

    def __init__(self, context=None, *args):
        super().__init__(context)
        self.setOrientation(LinearLayout.HORIZONTAL)
        self.setGravity(Gravity.CENTER_VERTICAL)
        self._checked = False
        self._indicator = View(context)
        self._label = TextView(context)
        self._label.setTextSize(16)
        self._label.setTextColor(0xFFFFFFFF)
        self._value = TextView(context)
        self._value.setTextSize(13)
        self._value.setTextColor(self.OFF)
        self._value.setVisibility(View.GONE)
        self._column = LinearLayout(context)
        self._column.setOrientation(LinearLayout.VERTICAL)
        self._column.addView(self._label, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        self._column.addView(self._value, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        indicator_params = LinearLayout.LayoutParams(self.SIZE, self.SIZE)
        indicator_params.setMargins(16, 12, 16, 12)
        self.addView(self._indicator, indicator_params)
        self.addView(self._column, LinearLayout.LayoutParams(0, WRAP_CONTENT, 1.0))
        self._paint()

    def _paint(self):
        shape = GradientDrawable()
        shape.setShape(GradientDrawable.OVAL)
        shape.setColor(self.ON if self._checked else 0)
        shape.setStroke(2, self.ON if self._checked else self.OFF)
        self._indicator.setBackground(shape)

    def setChecked(self, checked, *_animated):
        self._checked = bool(checked)
        self._paint()

    def isChecked(self):
        return self._checked

    def _set_texts(self, text, value):
        self._label.setText(text)
        self._value.setText(value or "")
        self._value.setVisibility(View.VISIBLE if value else View.GONE)


class CheckBoxCell(_CheckCell):
    def __init__(self, context=None, check_type=1, *_resources):
        super().__init__(context)

    def setText(self, text, value, checked, divider):
        self._set_texts(text, value)
        self.setChecked(checked)


class RadioColorCell(_CheckCell):
    def setCheckColor(self, off, on):
        self.OFF, self.ON = int(off) & 0xFFFFFFFF, int(on) & 0xFFFFFFFF
        self._paint()

    def setTextAndValue(self, text, checked):
        self._set_texts(text, "")
        self.setChecked(checked)


class TextCheckCell2(_CheckCell):
    """the row of a switch with a collapse arrow for a group of options: a collapsed group shows its count in the value line"""

    def __init__(self, context=None, *args):
        super().__init__(context)
        self._collapsed = False

    def setTextAndCheck(self, text, checked, divider=False):
        self._set_texts(text, self._value._text)
        self.setChecked(checked)

    def setCollapsed(self, collapsed):
        self._collapsed = bool(collapsed)
        self._column.setAlpha(0.6 if self._collapsed else 1.0)

    def isCollapsed(self):
        return self._collapsed

    def setValue(self, value):
        self._set_texts(self._label._text, value)
