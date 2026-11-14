"""org.telegram.ui.Components.Reactions"""

from java.lang import IllegalArgumentException, Object


class ReactionsLayoutInBubble(Object):
    """the reactions under a message of the android chat. the app draws its own, so of the class only VisibleReaction exists: the value that
    names one reaction, an emoji or a custom emoji, which plugins build and compare"""

    class VisibleReaction(Object):
        def __init__(self):
            self.emojicon = None
            self.documentId = 0
            self.isStar = False
            self.hash = 0
            self.sticker = False

        @staticmethod
        def fromEmojicon(emoji):
            if emoji is None:
                raise IllegalArgumentException("emoji == null")
            found = ReactionsLayoutInBubble.VisibleReaction()
            found.emojicon = str(emoji)
            found.hash = hash(found.emojicon) & 0x7FFFFFFF
            return found

        @staticmethod
        def fromCustomEmoji(document_id):
            found = ReactionsLayoutInBubble.VisibleReaction()
            found.documentId = int(document_id)
            found.hash = int(document_id) & 0x7FFFFFFF
            return found

        @staticmethod
        def fromTL(reaction):
            """a TL_reactionEmoji or TL_reactionCustomEmoji; any other record (the paid one, the empty one) is refused by name"""
            emoticon = getattr(reaction, "emoticon", None)
            document_id = getattr(reaction, "document_id", None)
            if emoticon is not None:
                return ReactionsLayoutInBubble.VisibleReaction.fromEmojicon(emoticon)
            if document_id is not None:
                return ReactionsLayoutInBubble.VisibleReaction.fromCustomEmoji(document_id)
            raise IllegalArgumentException("%r names no emoji and no custom emoji" % (reaction,))

        def _key(self):
            return (self.emojicon, int(self.documentId), bool(self.isStar))

        def equals(self, other):
            return isinstance(other, ReactionsLayoutInBubble.VisibleReaction) and self._key() == other._key()

        __eq__ = equals

        def hashCode(self):
            return hash(self._key()) & 0x7FFFFFFF

        __hash__ = hashCode

        def toString(self):
            return "VisibleReaction{%s}" % (self.emojicon if self.emojicon is not None else "custom:%d" % int(self.documentId))
