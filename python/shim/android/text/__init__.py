"""android.text"""


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
