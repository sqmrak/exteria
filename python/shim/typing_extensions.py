"""typing_extensions as far as plugins use it. python 3.11 has everything but deprecated, which came with 3.13"""

import functools
import warnings
from typing import get_args, get_origin, overload  # noqa: F401


def deprecated(message, *, category=DeprecationWarning, stacklevel=1):
    def decorate(function):
        @functools.wraps(function)
        def wrapper(*args, **kwargs):
            warnings.warn(message, category=category, stacklevel=stacklevel + 1)
            return function(*args, **kwargs)
        return wrapper
    return decorate
