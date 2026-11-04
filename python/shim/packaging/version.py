"""packaging.version.Version for the versions plugins compare: releases like 3.0.0 and 12.10.6 with the pre, post and dev
tags of pep 440. a local part (+abc) is accepted and ignored in the order, as an index would. anything else is InvalidVersion"""

import re

_PATTERN = re.compile(
    r"^\s*v?(?P<release>\d+(?:\.\d+)*)"
    r"(?:[-_.]?(?P<pre_tag>alpha|a|beta|b|preview|pre|c|rc)[-_.]?(?P<pre_number>\d*))?"
    r"(?:[-_.]?(?:post|rev|r)[-_.]?(?P<post>\d*))?"
    r"(?:[-_.]?dev[-_.]?(?P<dev>\d*))?"
    r"(?:\+[a-z0-9]+(?:[-_.][a-z0-9]+)*)?\s*$",
    re.IGNORECASE)
_PRE_ORDER = {"a": 0, "alpha": 0, "b": 1, "beta": 1, "c": 2, "rc": 2, "pre": 2, "preview": 2}


class InvalidVersion(ValueError):
    pass


class Version:
    def __init__(self, text):
        match = _PATTERN.match(str(text))
        if match is None:
            raise InvalidVersion("invalid version: %r" % (text,))
        self._text = str(text).strip()
        release = [int(part) for part in match.group("release").split(".")]
        while len(release) > 1 and release[-1] == 0:
            release.pop()
        tag = match.group("pre_tag")
        pre = (_PRE_ORDER[tag.lower()], int(match.group("pre_number") or 0)) if tag else None
        post = int(match.group("post") or 0) if match.group("post") is not None else None
        dev = int(match.group("dev") or 0) if match.group("dev") is not None else None
        self.release = tuple(release)
        # a dev release of a version sorts before its pre releases, a version without pre or post sorts after them
        pre_key = pre if pre is not None else ((-1, 0) if dev is not None and post is None else (3, 0))
        self._key = (self.release, pre_key, -1 if post is None else post, dev if dev is not None else 2 ** 62)

    def __str__(self):
        return self._text

    def __repr__(self):
        return "<Version('%s')>" % self._text

    def __hash__(self):
        return hash(self._key)

    def _other(self, other):
        return other._key if isinstance(other, Version) else Version(other)._key

    def __eq__(self, other):
        return self._key == self._other(other)

    def __lt__(self, other):
        return self._key < self._other(other)

    def __le__(self, other):
        return self._key <= self._other(other)

    def __gt__(self, other):
        return self._key > self._other(other)

    def __ge__(self, other):
        return self._key >= self._other(other)
